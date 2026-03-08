#!/usr/bin/env python3
"""Serve a lightweight dashboard for centralized AI CLI logs, with token cost analysis."""

from __future__ import annotations

import argparse
import gzip
import json
import os
import re
import threading
import time
import urllib.request
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Dict, Iterable, List, Tuple


DAY_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

# ---------------------------------------------------------------------------
# Pricing (pydantic/genai-prices)
# ---------------------------------------------------------------------------

PRICING_URL = "https://raw.githubusercontent.com/pydantic/genai-prices/main/prices/data_slim.json"
_PRICING_CACHE: list | None = None
_PRICING_CACHE_AT: float = 0.0
_PRICING_CACHE_TTL = 86_400  # 24 h


def _match_rule(model_id: str, rule: dict) -> bool:
    mid = model_id.lower()
    if "equals" in rule:
        return mid == rule["equals"].lower()
    if "starts_with" in rule:
        return mid.startswith(rule["starts_with"].lower())
    if "ends_with" in rule:
        return mid.endswith(rule["ends_with"].lower())
    if "contains" in rule:
        return rule["contains"].lower() in mid
    if "or" in rule:
        return any(_match_rule(model_id, r) for r in rule["or"])
    if "and" in rule:
        return all(_match_rule(model_id, r) for r in rule["and"])
    if "regex" in rule:
        try:
            return bool(re.search(rule["regex"], mid, re.IGNORECASE))
        except re.error:
            return False
    return False


def _flat_price(p: object) -> float:
    if isinstance(p, (int, float)):
        return float(p)
    if isinstance(p, dict):
        return float(p.get("base", 0))
    return 0.0


def fetch_pricing() -> list:
    global _PRICING_CACHE, _PRICING_CACHE_AT
    now = time.time()
    if _PRICING_CACHE and (now - _PRICING_CACHE_AT) < _PRICING_CACHE_TTL:
        return _PRICING_CACHE

    cache_path = Path.home() / ".cache" / "genai-prices-slim.json"
    if cache_path.exists() and (now - cache_path.stat().st_mtime) < _PRICING_CACHE_TTL:
        try:
            data = json.loads(cache_path.read_text())
            # Cache stores already-flattened model list (written by fetch path below).
            _PRICING_CACHE = data if isinstance(data, list) else []
            _PRICING_CACHE_AT = now
            return _PRICING_CACHE
        except Exception:
            pass

    try:
        with urllib.request.urlopen(PRICING_URL, timeout=8) as resp:
            raw = json.loads(resp.read())
        # data_slim.json is [{id:"anthropic", models:[{id, match, prices}]}, ...]
        # Flatten all provider.models into a single list.
        providers = raw if isinstance(raw, list) else [raw]
        models: list = []
        for provider in providers:
            if isinstance(provider, dict):
                models.extend(provider.get("models", []))
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        cache_path.write_text(json.dumps(models))
        _PRICING_CACHE = models
        _PRICING_CACHE_AT = now
        return models
    except Exception:
        return []


def model_prices(model_id: str, pricing: list) -> dict:
    for entry in pricing:
        if _match_rule(model_id, entry.get("match", {})):
            return entry.get("prices", {})
    return {}


def cost_usd(prices: dict, usage: dict) -> float:
    M = 1_000_000
    inp = (usage.get("input_tokens") or 0)
    out = (usage.get("output_tokens") or 0)
    cr = (usage.get("cache_read_input_tokens") or 0)
    cw = (usage.get("cache_creation_input_tokens") or 0)
    return (
        (inp / M) * _flat_price(prices.get("input_mtok", 0))
        + (out / M) * _flat_price(prices.get("output_mtok", 0))
        + (cr / M) * _flat_price(prices.get("cache_read_mtok", 0))
        + (cw / M) * _flat_price(prices.get("cache_write_mtok", 0))
    )


# ---------------------------------------------------------------------------
# File helpers
# ---------------------------------------------------------------------------

def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def open_text(path: Path):
    if path.suffix == ".gz":
        return gzip.open(path, mode="rt", encoding="utf-8", errors="ignore")
    return path.open(mode="rt", encoding="utf-8", errors="ignore")


def count_lines(path: Path) -> int:
    total = 0
    with open_text(path) as handle:
        for _ in handle:
            total += 1
    return total


# ---------------------------------------------------------------------------
# Cost summary — reads from ~/logs/ai/vector/*.jsonl
# ---------------------------------------------------------------------------

def build_cost_summary(vector_root: Path) -> dict:
    pricing = fetch_pricing()
    pricing_loaded = len(pricing) > 0

    claude_models: dict[str, dict] = defaultdict(lambda: {
        "cost_usd": 0.0,
        "input_tokens": 0,
        "output_tokens": 0,
        "cache_read_tokens": 0,
        "cache_write_tokens": 0,
        "events": 0,
    })
    claude_tools: dict[str, int] = defaultdict(int)
    claude_agents: dict[str, int] = defaultdict(int)  # subagent_type → count
    claude_sidechain_events = 0
    claude_sessions: set = set()

    codex_stats = {
        "input_tokens": 0,
        "output_tokens": 0,
        "cached_tokens": 0,
        "reasoning_tokens": 0,
        "events": 0,
        "sessions": set(),
        "tasks": 0,
        "plans": 0,
        "agent_messages": 0,
    }

    cursor_by_tool: dict[str, int] = defaultdict(int)
    cursor_total = 0

    copilot_stats = {"tool_calls": 0, "sessions": set()}

    if not vector_root.exists():
        return {"error": f"vector root not found: {vector_root}", "pricing_loaded": False}

    for shard in sorted(vector_root.glob("*.jsonl*")):
        try:
            with open_text(shard) as f:
                for line in f:
                    try:
                        e = json.loads(line)
                    except Exception:
                        continue

                    src = e.get("source", "")

                    if src == "claude-code":
                        sid = e.get("sessionId") or e.get("session") or ""
                        if sid:
                            claude_sessions.add(sid)
                        if e.get("isSidechain"):
                            claude_sidechain_events += 1

                        if e.get("type") == "assistant":
                            msg = e.get("message") or {}
                            model = msg.get("model") or ""
                            usage = msg.get("usage") or {}
                            if model and usage:
                                prices = model_prices(model, pricing)
                                rec = claude_models[model]
                                rec["events"] += 1
                                rec["input_tokens"] += usage.get("input_tokens") or 0
                                rec["output_tokens"] += usage.get("output_tokens") or 0
                                rec["cache_read_tokens"] += usage.get("cache_read_input_tokens") or 0
                                rec["cache_write_tokens"] += usage.get("cache_creation_input_tokens") or 0
                                rec["cost_usd"] += cost_usd(prices, usage)
                            # Count tool calls
                            for block in (msg.get("content") or []):
                                if isinstance(block, dict) and block.get("type") == "tool_use":
                                    name = block.get("name", "?")
                                    claude_tools[name] += 1
                                    if name == "Agent":
                                        st = (block.get("input") or {}).get("subagent_type", "?")
                                        claude_agents[st] += 1

                    elif src == "codex" and e.get("type") == "event_msg":
                        payload = e.get("payload") or {}
                        ptype = payload.get("type")
                        if ptype == "token_count":
                            info = payload.get("info") or {}
                            tu = info.get("last_token_usage") or {}
                            codex_stats["input_tokens"] += tu.get("input_tokens") or 0
                            codex_stats["output_tokens"] += tu.get("output_tokens") or 0
                            codex_stats["cached_tokens"] += tu.get("cached_input_tokens") or 0
                            codex_stats["reasoning_tokens"] += tu.get("reasoning_output_tokens") or 0
                            codex_stats["events"] += 1
                        elif ptype == "task_started":
                            codex_stats["tasks"] += 1
                        elif ptype == "agent_message":
                            codex_stats["agent_messages"] += 1
                        elif ptype == "item_completed":
                            item = payload.get("item") or {}
                            if item.get("type") == "Plan":
                                codex_stats["plans"] += 1
                        if e.get("session"):
                            codex_stats["sessions"].add(e["session"])

                    elif src == "codex" and e.get("type") == "session_meta":
                        sid = (e.get("payload") or {}).get("id") or e.get("session") or ""
                        if sid:
                            codex_stats["sessions"].add(sid)

                    elif src == "cursor-cost":
                        tok = e.get("tokens") or 0
                        tool = e.get("tool") or "unknown"
                        cursor_by_tool[tool] += tok
                        cursor_total += tok

                    elif src == "copilot":
                        t = e.get("type", "")
                        if t in ("tool.execution_start", "tool.execution_complete"):
                            copilot_stats["tool_calls"] += 1
                        sid = (e.get("data") or {}).get("sessionId") or ""
                        if sid:
                            copilot_stats["sessions"].add(sid)

        except Exception:
            continue

    # --- Read Codex from ~/logs/ai/codex/ (normalized by OpenClaw, has model+token data) ---
    # Falls back to ~/.codex/sessions/ if the normalized dir is absent.
    codex_raw_models: dict[str, dict] = defaultdict(lambda: {
        "cost_usd": 0.0,
        "input_tokens": 0,
        "output_tokens": 0,
        "cached_tokens": 0,
        "reasoning_tokens": 0,
        "events": 0,
    })
    _norm_codex = Path.home() / "logs" / "ai" / "codex"
    _raw_codex = Path.home() / ".codex" / "sessions"
    codex_dir = _norm_codex if _norm_codex.exists() else _raw_codex
    _is_normalized = codex_dir == _norm_codex
    if codex_dir.exists():
        for codex_file in sorted(codex_dir.rglob("*.jsonl")):
            try:
                with open_text(codex_file) as f:
                    current_model = ""
                    for line in f:
                        try:
                            e = json.loads(line)
                        except Exception:
                            continue
                        t = e.get("type", "")
                        payload = e.get("payload") or {}
                        if t == "turn_context":
                            current_model = payload.get("model", "") or current_model
                        elif t == "event_msg" and payload.get("type") == "token_count":
                            info = payload.get("info") or {}
                            tu = info.get("last_token_usage") or {}
                            if tu and current_model:
                                rec = codex_raw_models[current_model]
                                inp = tu.get("input_tokens", 0) or 0
                                out = tu.get("output_tokens", 0) or 0
                                cached = tu.get("cached_input_tokens", 0) or 0
                                reasoning = tu.get("reasoning_output_tokens", 0) or 0
                                prices = model_prices(current_model, pricing)
                                usage_for_cost = {
                                    "input_tokens": inp,
                                    "output_tokens": out,
                                    "cache_read_input_tokens": cached,
                                    "cache_creation_input_tokens": 0,
                                }
                                rec["input_tokens"] += inp
                                rec["output_tokens"] += out
                                rec["cached_tokens"] += cached
                                rec["reasoning_tokens"] += reasoning
                                rec["events"] += 1
                                rec["cost_usd"] += cost_usd(prices, usage_for_cost)
            except Exception:
                continue

    total_cost = sum(m["cost_usd"] for m in claude_models.values())
    codex_cost_total = sum(m["cost_usd"] for m in codex_raw_models.values())

    return {
        "generated_at": now_iso(),
        "pricing_loaded": pricing_loaded,
        "pricing_model_count": len(pricing),
        "total_cost_usd": total_cost,
        "codex_cost_total": codex_cost_total,
        "codex_models": {
            model: {**stats}
            for model, stats in sorted(codex_raw_models.items(), key=lambda x: -x[1]["cost_usd"])
        },
        "claude": {
            model: {**stats}
            for model, stats in sorted(claude_models.items(), key=lambda x: -x[1]["cost_usd"])
        },
        "claude_activity": {
            "sessions": len(claude_sessions),
            "sidechain_events": claude_sidechain_events,
            "total_tool_calls": sum(claude_tools.values()),
            "agent_dispatches": sum(claude_agents.values()),
            "tools": dict(sorted(claude_tools.items(), key=lambda x: -x[1])),
            "agents": dict(sorted(claude_agents.items(), key=lambda x: -x[1])),
        },
        "codex": {
            **{k: v for k, v in codex_stats.items() if k != "sessions"},
            "sessions": len(codex_stats["sessions"]),
        },
        "cursor": {
            "total_tokens": cursor_total,
            "by_tool": dict(sorted(cursor_by_tool.items(), key=lambda x: -x[1])),
        },
        "copilot": {
            "tool_calls": copilot_stats["tool_calls"],
            "sessions": len(copilot_stats["sessions"]),
        },
    }


# ---------------------------------------------------------------------------
# Vector pipeline health (queries Vector GraphQL API)
# ---------------------------------------------------------------------------

VECTOR_API = "http://127.0.0.1:9598/graphql"

_PIPELINE_QUERY = """
{
  sources { edges { node {
    componentId componentType
    metrics {
      sentEventsTotal { sentEventsTotal }
      receivedBytesTotal { receivedBytesTotal }
    }
  }}}
  transforms { edges { node {
    componentId componentType
    metrics {
      sentEventsTotal { sentEventsTotal }
    }
  }}}
  sinks { edges { node {
    componentId componentType
    metrics {
      sentEventsTotal { sentEventsTotal }
      sentBytesTotal { sentBytesTotal }
    }
  }}}
}
"""


def fetch_vector_pipeline() -> dict:
    try:
        data = json.dumps({"query": _PIPELINE_QUERY}).encode()
        req = urllib.request.Request(
            VECTOR_API,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=3) as resp:
            body = json.loads(resp.read())
        if "errors" in body:
            return {"error": body["errors"][0]["message"], "online": False}

        d = body.get("data") or {}

        def extract(section: str) -> list:
            # sources expose receivedBytesTotal; sinks expose sentBytesTotal
            bytes_field = "receivedBytesTotal" if section == "sources" else "sentBytesTotal"
            rows = []
            for edge in (d.get(section) or {}).get("edges") or []:
                node = edge.get("node") or {}
                m = node.get("metrics") or {}
                rows.append({
                    "id": node.get("componentId", "?"),
                    "kind": section.rstrip("s"),   # sources→source
                    "events": int((m.get("sentEventsTotal") or {}).get("sentEventsTotal") or 0),
                    "bytes": int((m.get(bytes_field) or {}).get(bytes_field) or 0),
                })
            return rows

        components = extract("sources") + extract("transforms") + extract("sinks")
        total_events = sum(c["events"] for c in components if c["kind"] == "source")
        total_bytes = sum(c["bytes"] for c in components if c["kind"] == "source")

        return {
            "online": True,
            "generated_at": now_iso(),
            "components": components,
            "total_events": total_events,
            "total_bytes": total_bytes,
        }
    except Exception as exc:
        return {"online": False, "error": str(exc)}


# ---------------------------------------------------------------------------
# Log summary (existing)
# ---------------------------------------------------------------------------

@dataclass
class DashboardState:
    root: Path
    vector_root: Path
    cache_ttl: int
    _lock: threading.Lock = field(default_factory=threading.Lock)
    _cached_at: float = 0.0
    _cached_summary: Dict | None = None
    _cost_lock: threading.Lock = field(default_factory=threading.Lock)
    _cost_cached_at: float = 0.0
    _cost_cached: Dict | None = None
    _pipeline_lock: threading.Lock = field(default_factory=threading.Lock)
    _pipeline_cached_at: float = 0.0
    _pipeline_cached: Dict | None = None

    def get_summary(self) -> Dict:
        with self._lock:
            now = time.time()
            if self._cached_summary and (now - self._cached_at) < self.cache_ttl:
                return self._cached_summary
            summary = build_summary(self.root)
            self._cached_summary = summary
            self._cached_at = now
            return summary

    def get_costs(self) -> Dict:
        with self._cost_lock:
            now = time.time()
            if self._cost_cached and (now - self._cost_cached_at) < 15:
                return self._cost_cached
            costs = build_cost_summary(self.vector_root)
            self._cost_cached = costs
            self._cost_cached_at = now
            return costs

    def get_pipeline(self) -> Dict:
        with self._pipeline_lock:
            now = time.time()
            if self._pipeline_cached and (now - self._pipeline_cached_at) < 5:
                return self._pipeline_cached
            data = fetch_vector_pipeline()
            self._pipeline_cached = data
            self._pipeline_cached_at = now
            return data


def _scan_day(tool: str, day_dir: Path) -> Iterable[Tuple[str, str, str, Path]]:
    """Yield (day, session, tool, path) for a single day directory."""
    for session_dir in day_dir.iterdir():
        if not session_dir.is_dir():
            continue

        session = session_dir.name

        for name in ("events.jsonl", "events.jsonl.gz"):
            file_path = session_dir / name
            if file_path.exists() and file_path.is_file():
                yield day_dir.name, session, tool, file_path

        for log_type in ("json", "text"):
            type_dir = session_dir / log_type
            if not type_dir.is_dir():
                continue
            for name in ("events.jsonl", "events.jsonl.gz"):
                file_path = type_dir / name
                if file_path.exists() and file_path.is_file():
                    yield day_dir.name, session, tool, file_path


def iter_event_files(root: Path) -> Iterable[Tuple[str, str, str, Path]]:
    if not root.exists():
        return

    for tool_dir in sorted(root.iterdir()):
        if not tool_dir.is_dir() or tool_dir.name.startswith("."):
            continue

        has_day_children = any(
            DAY_RE.match(c.name) for c in tool_dir.iterdir() if c.is_dir()
        )
        if has_day_children:
            for day_dir in sorted(tool_dir.iterdir(), reverse=True):
                if day_dir.is_dir() and DAY_RE.match(day_dir.name):
                    yield from _scan_day(tool_dir.name, day_dir)
        else:
            if DAY_RE.match(tool_dir.name):
                yield from _scan_day("claude", tool_dir)


def build_summary(root: Path) -> Dict:
    totals = {
        "days": 0,
        "sessions": 0,
        "files": 0,
        "events": 0,
        "bytes": 0,
        "newest_file_mtime": None,
    }

    sessions: Dict[str, Dict] = defaultdict(
        lambda: {
            "events": 0,
            "bytes": 0,
            "files": 0,
            "days": set(),
            "last_seen_epoch": 0,
        }
    )
    days: Dict[str, Dict] = defaultdict(
        lambda: {
            "events": 0,
            "bytes": 0,
            "files": 0,
            "sessions": set(),
        }
    )
    by_agent: Dict[str, Dict] = defaultdict(
        lambda: {"events": 0, "bytes": 0, "files": 0},
    )

    for day, session, tool, file_path in iter_event_files(root):
        try:
            event_count = count_lines(file_path)
        except OSError:
            continue

        stat = file_path.stat()
        size_bytes = stat.st_size
        mtime = stat.st_mtime

        totals["files"] += 1
        totals["events"] += event_count
        totals["bytes"] += size_bytes

        newest = totals["newest_file_mtime"]
        totals["newest_file_mtime"] = mtime if newest is None else max(newest, mtime)

        session_rec = sessions[session]
        session_rec["events"] += event_count
        session_rec["bytes"] += size_bytes
        session_rec["files"] += 1
        session_rec["days"].add(day)
        session_rec["last_seen_epoch"] = max(session_rec["last_seen_epoch"], mtime)
        session_rec.setdefault("agent", tool)

        day_rec = days[day]
        day_rec["events"] += event_count
        day_rec["bytes"] += size_bytes
        day_rec["files"] += 1
        day_rec["sessions"].add(session)

        by_agent[tool]["events"] += event_count
        by_agent[tool]["bytes"] += size_bytes
        by_agent[tool]["files"] += 1

    totals["days"] = len(days)
    totals["sessions"] = len(sessions)
    newest_mtime = totals["newest_file_mtime"]
    totals["newest_file_mtime"] = (
        datetime.fromtimestamp(newest_mtime, tz=timezone.utc)
        .isoformat()
        .replace("+00:00", "Z")
        if newest_mtime
        else None
    )

    top_sessions: List[Dict] = []
    for session, rec in sessions.items():
        top_sessions.append(
            {
                "session": session,
                "agent": rec.get("agent", "unknown"),
                "events": rec["events"],
                "bytes": rec["bytes"],
                "files": rec["files"],
                "days": len(rec["days"]),
                "last_seen": datetime.fromtimestamp(
                    rec["last_seen_epoch"], tz=timezone.utc
                )
                .isoformat()
                .replace("+00:00", "Z"),
            }
        )

    top_sessions.sort(key=lambda item: item["events"], reverse=True)

    day_rows: List[Dict] = []
    for day, rec in days.items():
        day_rows.append(
            {
                "day": day,
                "events": rec["events"],
                "bytes": rec["bytes"],
                "files": rec["files"],
                "sessions": len(rec["sessions"]),
            }
        )
    day_rows.sort(key=lambda item: item["day"], reverse=True)

    return {
        "generated_at": now_iso(),
        "root": str(root),
        "totals": totals,
        "agents": by_agent,
        "days": day_rows,
        "top_sessions": top_sessions[:20],
    }


# ---------------------------------------------------------------------------
# HTML
# ---------------------------------------------------------------------------

HTML_TEMPLATE = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>AI Logs Dashboard</title>
  <style>
    :root {
      --bg-a: #0b1320;
      --bg-b: #0f1a2b;
      --bg-c: #0a121f;
      --card: #111b2b;
      --card-strong: #0c1624;
      --ink: #eaf1fc;
      --muted: #9fb1c8;
      --line: #203047;
      --line-soft: #1a273c;
      --accent: #4da3ff;
      --accent-soft: #1a2c45;
      --json: #40b8ff;
      --text: #f9b266;
      --good: #4bc08c;
      --warn: #f0a840;
      --shadow: 0 8px 18px rgba(1, 8, 18, 0.24);
    }

    * { box-sizing: border-box; }

    body {
      margin: 0;
      font-family: "Plus Jakarta Sans", "IBM Plex Sans", "Avenir Next", "Segoe UI", sans-serif;
      color: var(--ink);
      background:
        radial-gradient(1000px 620px at -10% -18%, #17335d 0%, transparent 58%),
        radial-gradient(1000px 620px at 112% 118%, #1b3552 0%, transparent 56%),
        linear-gradient(150deg, var(--bg-a), var(--bg-b) 54%, var(--bg-c));
      min-height: 100vh;
      padding: 14px;
    }

    body::before {
      content: "";
      position: fixed;
      inset: 0;
      pointer-events: none;
      background-image:
        linear-gradient(rgba(120, 150, 190, 0.06) 1px, transparent 1px),
        linear-gradient(90deg, rgba(120, 150, 190, 0.06) 1px, transparent 1px);
      background-size: 28px 28px;
      opacity: 0.16;
      mask-image: radial-gradient(circle at 30% 20%, black 20%, transparent 75%);
    }

    .wrap { max-width: 1480px; margin: 0 auto; }

    .header {
      display: flex;
      align-items: end;
      justify-content: space-between;
      gap: 12px;
      margin-bottom: 10px;
    }

    h1 {
      margin: 0;
      font-size: 27px;
      letter-spacing: 0.16px;
      font-weight: 700;
    }

    .sub {
      color: var(--muted);
      margin-top: 3px;
      font-size: 12px;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .section-label {
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 0.7px;
      text-transform: uppercase;
      color: var(--muted);
      margin: 14px 0 6px 2px;
    }

    .kpi-grid {
      display: grid;
      grid-template-columns: repeat(10, minmax(0, 1fr));
      gap: 8px;
      margin-bottom: 10px;
    }

    .kpi-grid-4 {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 8px;
    }

    .kpi-grid-5 {
      display: grid;
      grid-template-columns: repeat(5, minmax(0, 1fr));
      gap: 8px;
      margin-bottom: 10px;
    }

    @media (max-width: 1240px) {
      .kpi-grid { grid-template-columns: repeat(5, minmax(0, 1fr)); }
    }

    @media (max-width: 740px) {
      .kpi-grid, .kpi-grid-4, .kpi-grid-5 { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .header { flex-direction: column; align-items: start; }
    }

    .card {
      background: linear-gradient(180deg, #142238 0%, var(--card) 100%);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 10px;
      box-shadow: var(--shadow);
      animation: card-enter 180ms ease both;
    }

    .kpi {
      min-height: 72px;
      border-color: var(--line-soft);
    }

    .k {
      color: var(--muted);
      font-size: 10px;
      text-transform: uppercase;
      letter-spacing: 0.58px;
      font-weight: 600;
    }

    .v {
      font-size: 24px;
      font-weight: 700;
      margin-top: 4px;
      line-height: 1.1;
    }

    .v-small {
      font-size: 16px;
      margin-top: 7px;
      color: #d5e4f9;
      font-weight: 650;
    }

    .v-cost {
      font-size: 22px;
      font-weight: 700;
      margin-top: 4px;
      color: var(--good);
    }

    .main {
      display: grid;
      grid-template-columns: 2fr 1fr;
      gap: 8px;
      margin-bottom: 8px;
    }

    @media (max-width: 1020px) {
      .main { grid-template-columns: 1fr; }
    }

    h2 {
      margin: 1px 0 8px 0;
      font-size: 13px;
      letter-spacing: 0.22px;
      font-weight: 680;
    }

    .panel {
      display: grid;
      gap: 8px;
    }

    .chart-card {
      height: 220px;
      display: grid;
      grid-template-rows: auto 1fr;
    }

    .bars {
      display: grid;
      align-items: end;
      height: 170px;
      gap: 2px;
      grid-template-columns: repeat(21, minmax(0, 1fr));
      padding-top: 6px;
    }

    .bar-col {
      border-radius: 3px 3px 0 0;
      background: linear-gradient(180deg, #4ca8ff 0%, #2f71c5 100%);
      min-height: 2px;
      opacity: 0.92;
      transition: opacity 140ms ease;
    }

    .bar-col:hover { opacity: 1; }

    .chart-meta {
      font-size: 11px;
      color: var(--muted);
      display: flex;
      justify-content: space-between;
      margin-top: 6px;
    }

    .split-grid {
      display: grid;
      grid-template-columns: 120px 1fr;
      gap: 10px;
      align-items: center;
    }

    .donut {
      width: 104px;
      height: 104px;
      border-radius: 50%;
      background: conic-gradient(var(--json) 0deg var(--json-deg), var(--text) var(--json-deg) 360deg);
      position: relative;
      border: 1px solid var(--line);
      margin: 0 auto;
    }

    .donut::after {
      content: "";
      position: absolute;
      inset: 20px;
      border-radius: 50%;
      background: var(--card-strong);
      border: 1px solid var(--line-soft);
    }

    .donut-center {
      position: absolute;
      inset: 0;
      display: grid;
      place-items: center;
      z-index: 1;
      font-size: 12px;
      color: #d8e6f9;
      font-weight: 650;
    }

    .legend {
      display: grid;
      gap: 8px;
      font-size: 12px;
    }

    .legend-item {
      display: grid;
      grid-template-columns: 12px 1fr auto;
      gap: 8px;
      align-items: center;
    }

    .swatch { width: 10px; height: 10px; border-radius: 2px; }
    .swatch.json { background: var(--json); }
    .swatch.text { background: var(--text); }

    .session-bars {
      display: grid;
      gap: 6px;
      margin-top: 4px;
      font-size: 11px;
    }

    .session-row {
      display: grid;
      grid-template-columns: 1fr 62px;
      gap: 8px;
      align-items: center;
    }

    .session-name {
      color: #d7e6fb;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      margin-bottom: 3px;
    }

    .session-track {
      background: #10213a;
      height: 8px;
      border-radius: 999px;
      border: 1px solid var(--line);
      overflow: hidden;
    }

    .session-fill {
      height: 100%;
      background: linear-gradient(90deg, #468fe0, #61b2ff);
      border-radius: 999px;
    }

    .session-val {
      text-align: right;
      color: var(--muted);
      font-variant-numeric: tabular-nums;
    }

    table { width: 100%; border-collapse: collapse; }
    th, td {
      text-align: left;
      font-size: 12px;
      padding: 7px 6px;
      border-bottom: 1px solid var(--line);
    }

    th {
      color: var(--muted);
      font-weight: 600;
      font-size: 11px;
      letter-spacing: 0.35px;
      text-transform: uppercase;
    }

    tr:last-child td { border-bottom: none; }
    tbody tr:hover { background: rgba(67, 110, 168, 0.19); }

    .table-card {
      max-height: 350px;
      overflow: auto;
      margin-bottom: 8px;
    }

    .cost-highlight { color: var(--good); font-weight: 700; }
    .note { color: var(--muted); font-size: 11px; margin: 4px 0 8px 0; }

    .foot {
      margin-top: 4px;
      color: var(--muted);
      font-size: 11px;
    }

    @keyframes card-enter {
      from { opacity: 0; transform: translateY(6px); }
      to   { opacity: 1; transform: translateY(0); }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="header">
      <div>
        <h1>AI Logs Dashboard</h1>
        <div class="sub" id="sub">Loading...</div>
      </div>
      <div class="sub" id="header-meta">Auto refresh</div>
    </div>

    <!-- ── Activity KPIs ── -->
    <div class="section-label">Activity</div>
    <div class="kpi-grid">
      <div class="card kpi"><div class="k">Events</div><div class="v" id="events">-</div></div>
      <div class="card kpi"><div class="k">Sessions</div><div class="v" id="sessions">-</div></div>
      <div class="card kpi"><div class="k">Day Shards</div><div class="v" id="days">-</div></div>
      <div class="card kpi"><div class="k">Files</div><div class="v" id="files">-</div></div>
      <div class="card kpi"><div class="k">Storage</div><div class="v" id="bytes">-</div></div>
      <div class="card kpi"><div class="k">Events / Day</div><div class="v-small" id="events-per-day">-</div></div>
      <div class="card kpi"><div class="k">Events / Session</div><div class="v-small" id="events-per-session">-</div></div>
      <div class="card kpi"><div class="k">Top Session Share</div><div class="v-small" id="top-share">-</div></div>
      <div class="card kpi"><div class="k">Agents</div><div class="v-small" id="agent-count">-</div></div>
      <div class="card kpi"><div class="k">7 Day Events</div><div class="v-small" id="events-7d">-</div></div>
    </div>

    <!-- ── Trends / Session breakdown ── -->
    <div class="main">
      <div class="panel">
        <div class="card chart-card">
          <h2>Daily Event Trend (latest 21 shards)</h2>
          <div>
            <div class="bars" id="trend-bars"></div>
            <div class="chart-meta">
              <span id="trend-min">Min: -</span>
              <span id="trend-max">Max: -</span>
              <span id="trend-total">Total: -</span>
            </div>
          </div>
        </div>
        <div class="card table-card">
          <h2>Daily Volume</h2>
          <table id="days-table">
            <thead><tr><th>Day</th><th>Events</th><th>Sessions</th><th>Files</th><th>Storage</th></tr></thead>
            <tbody></tbody>
          </table>
        </div>
      </div>

      <div class="panel">
        <div class="card">
          <h2>Agent Split</h2>
          <div class="split-grid">
            <div class="donut" id="agents-donut" style="--json-deg:180deg;">
              <div class="donut-center" id="donut-center">-</div>
            </div>
            <div class="legend" id="agents-legend"></div>
          </div>
        </div>
        <div class="card">
          <h2>Session Concentration (Top 8)</h2>
          <div class="session-bars" id="session-bars"></div>
        </div>
      </div>
    </div>

    <div class="card table-card">
      <h2>Top Sessions</h2>
      <table id="sessions-table">
        <thead><tr><th>Session</th><th>Agent</th><th>Events</th><th>Days</th><th>Files</th><th>Last Seen</th></tr></thead>
        <tbody></tbody>
      </table>
    </div>

    <!-- ── Cost KPIs ── -->
    <div class="section-label">Token Cost</div>
    <div class="kpi-grid-5">
      <div class="card kpi"><div class="k">Claude Code Cost</div><div class="v-cost" id="cost-total">-</div></div>
      <div class="card kpi"><div class="k">Codex Cost</div><div class="v-cost" id="codex-cost-total">-</div></div>
      <div class="card kpi"><div class="k">Codex Cache Tokens</div><div class="v-small" id="codex-cached">-</div></div>
      <div class="card kpi"><div class="k">Cursor Tokens</div><div class="v-small" id="cursor-tokens-total">-</div></div>
      <div class="card kpi"><div class="k">Combined Cost</div><div class="v-cost" id="cost-combined">-</div></div>
    </div>

    <div class="card table-card">
      <h2>Claude Code — Cost by Model</h2>
      <p class="note">Pricing via pydantic/genai-prices. Cache read/write tokens are billed at reduced rates.</p>
      <table id="cost-table">
        <thead><tr><th>Model</th><th>Calls</th><th>Input</th><th>Output</th><th>Cache Read</th><th>Cache Write</th><th>Cost (USD)</th></tr></thead>
        <tbody></tbody>
      </table>
    </div>
    <div class="card table-card">
      <h2>Codex — Cost by Model</h2>
      <p class="note">Read from ~/.codex/sessions. Cached input tokens billed at cache_read rate.</p>
      <table id="codex-cost-table">
        <thead><tr><th>Model</th><th>Events</th><th>Input</th><th>Output</th><th>Cached</th><th>Reasoning</th><th>Cost (USD)</th></tr></thead>
        <tbody></tbody>
      </table>
    </div>

    <!-- ── Tool Activity ── -->
    <div class="section-label">Tool Activity</div>
    <div class="main">
      <div class="card">
        <h2>Claude Code</h2>
        <div class="kpi-grid-4" style="margin-bottom:12px">
          <div class="card kpi"><div class="k">Sessions</div><div class="v" id="claude-act-sessions">-</div></div>
          <div class="card kpi"><div class="k">Tool Calls</div><div class="v-small" id="claude-act-tools">-</div></div>
          <div class="card kpi"><div class="k">Agent Dispatches</div><div class="v-small" id="claude-act-agents">-</div></div>
          <div class="card kpi"><div class="k">Sidechain Events</div><div class="v-small" id="claude-act-sidechain">-</div></div>
        </div>
        <h3 style="font-size:11px;color:var(--muted);margin:8px 0 4px">Top Tools</h3>
        <table id="claude-tools-table">
          <thead><tr><th>Tool</th><th>Calls</th></tr></thead>
          <tbody></tbody>
        </table>
        <h3 style="font-size:11px;color:var(--muted);margin:12px 0 4px">Agent Dispatches by Type</h3>
        <table id="claude-agents-table">
          <thead><tr><th>Subagent Type</th><th>Dispatches</th></tr></thead>
          <tbody></tbody>
        </table>
      </div>
      <div class="card">
        <h2>Codex</h2>
        <div class="kpi-grid-4" style="margin-bottom:12px">
          <div class="card kpi"><div class="k">Sessions</div><div class="v" id="codex-act-sessions">-</div></div>
          <div class="card kpi"><div class="k">Tasks</div><div class="v-small" id="codex-act-tasks">-</div></div>
          <div class="card kpi"><div class="k">Plans</div><div class="v-small" id="codex-act-plans">-</div></div>
          <div class="card kpi"><div class="k">Agent Messages</div><div class="v-small" id="codex-act-msgs">-</div></div>
        </div>
        <p class="note" style="margin-top:8px">Codex has no structured tool call log. Tasks = <code>task_started</code> events, Plans = completed plan items, Agent Messages = <code>agent_message</code> events.</p>
      </div>
    </div>

    <div class="main">
      <div class="card table-card">
        <h2>Cursor — Tokens by Tool</h2>
        <table id="cursor-table">
          <thead><tr><th>Tool</th><th>Tokens</th></tr></thead>
          <tbody></tbody>
        </table>
      </div>
      <div class="card">
        <h2>Other Tools</h2>
        <div id="other-tools-stats" style="font-size:12px;line-height:1.9;color:#d5e4f9;"></div>
        <p class="note" id="pricing-note"></p>
      </div>
    </div>

    <!-- ── Vector Pipeline Health ── -->
    <div class="section-label">Vector Pipeline</div>
    <div class="kpi-grid-5" id="pipeline-kpis">
      <div class="card kpi"><div class="k">Status</div><div class="v-small" id="pipeline-status">-</div></div>
      <div class="card kpi"><div class="k">Sources</div><div class="v" id="pipeline-sources">-</div></div>
      <div class="card kpi"><div class="k">Transforms</div><div class="v" id="pipeline-transforms">-</div></div>
      <div class="card kpi"><div class="k">Events (sources)</div><div class="v-small" id="pipeline-events">-</div></div>
      <div class="card kpi"><div class="k">Bytes (sources)</div><div class="v-small" id="pipeline-bytes">-</div></div>
    </div>
    <div class="card table-card">
      <h2>Component Throughput</h2>
      <table id="pipeline-table">
        <thead><tr><th>Component</th><th>Kind</th><th>Events Sent</th><th>Bytes Sent</th></tr></thead>
        <tbody></tbody>
      </table>
    </div>

    <div class="foot" id="foot"></div>
  </div>

  <script>
    const REFRESH_MS = REFRESH_MS_PLACEHOLDER;

    function esc(str) {
      const el = document.createElement('span');
      el.textContent = str;
      return el.innerHTML;
    }

    function fmtInt(value) {
      return new Intl.NumberFormat().format(value || 0);
    }

    function fmtBytes(bytes) {
      if (!bytes) return '0 B';
      const units = ['B', 'KB', 'MB', 'GB', 'TB'];
      let i = 0, n = bytes;
      while (n >= 1024 && i < units.length - 1) { n /= 1024; i++; }
      return `${n.toFixed(n >= 10 || i === 0 ? 0 : 1)} ${units[i]}`;
    }

    function fmtPct(value) {
      if (!Number.isFinite(value)) return '0.0%';
      return `${value.toFixed(1)}%`;
    }

    function fmtCost(usd) {
      if (!Number.isFinite(usd) || usd === 0) return '$0.00';
      if (usd < 0.01) return `$${usd.toFixed(4)}`;
      return `$${usd.toFixed(2)}`;
    }

    function shortTs(value) {
      if (!value) return 'n/a';
      const d = new Date(value);
      if (Number.isNaN(d.getTime())) return value;
      return d.toISOString().replace('T', ' ').slice(0, 16) + 'Z';
    }

    function setText(id, text) {
      const el = document.getElementById(id);
      if (el) el.textContent = text;
    }

    function renderDays(days) {
      const tbody = document.querySelector('#days-table tbody');
      tbody.innerHTML = '';
      for (const item of days.slice(0, 21)) {
        const tr = document.createElement('tr');
        tr.innerHTML = `<td>${esc(item.day)}</td><td>${fmtInt(item.events)}</td><td>${fmtInt(item.sessions)}</td><td>${fmtInt(item.files)}</td><td>${fmtBytes(item.bytes)}</td>`;
        tbody.appendChild(tr);
      }
    }

    const AGENT_COLORS = {
      'claude-code': '#4da3ff', claude: '#4da3ff',
      codex: '#f9b266', opencode: '#4bc08c',
      copilot: '#c084fc', cursor: '#fb7185',
      gemini: '#34d399',
    };

    function renderAgents(tools) {
      const entries = Object.entries(tools || {}).map(([name, rec]) => ({ name, events: rec.events || 0 }));
      entries.sort((a, b) => b.events - a.events);
      const total = entries.reduce((sum, item) => sum + item.events, 0);

      const donut = document.getElementById('agents-donut');
      let gradParts = [], cursor = 0;
      for (const item of entries) {
        const pct = total > 0 ? (item.events / total) * 100 : 0;
        const color = AGENT_COLORS[item.name] || '#888';
        gradParts.push(`${color} ${cursor}deg ${cursor + (pct / 100) * 360}deg`);
        cursor += (pct / 100) * 360;
      }
      donut.style.background = gradParts.length ? `conic-gradient(${gradParts.join(', ')})` : 'var(--card)';
      setText('donut-center', `${entries.length}`);

      const root = document.getElementById('agents-legend');
      root.innerHTML = '';
      for (const item of entries) {
        const pct = total > 0 ? (item.events / total) * 100 : 0;
        const color = AGENT_COLORS[item.name] || '#888';
        const row = document.createElement('div');
        row.className = 'legend-item';
        row.innerHTML = `
          <div class="swatch" style="background:${color}"></div>
          <div>${esc(item.name)} (${fmtPct(pct)})</div>
          <div>${fmtInt(item.events)}</div>
        `;
        root.appendChild(row);
      }
    }

    function renderTrend(days) {
      const items = (days || []).slice(0, 21).reverse();
      const maxEvents = Math.max(...items.map((x) => x.events || 0), 1);
      const minEvents = items.length ? Math.min(...items.map((x) => x.events || 0)) : 0;
      const totalEvents = items.reduce((sum, x) => sum + (x.events || 0), 0);

      const root = document.getElementById('trend-bars');
      root.innerHTML = '';
      for (const item of items) {
        const col = document.createElement('div');
        col.className = 'bar-col';
        const pct = Math.max(2, Math.round(((item.events || 0) / maxEvents) * 100));
        col.style.height = `${pct}%`;
        col.title = `${item.day}: ${fmtInt(item.events || 0)} events`;
        root.appendChild(col);
      }

      setText('trend-min', `Min: ${fmtInt(minEvents)}`);
      setText('trend-max', `Max: ${fmtInt(maxEvents)}`);
      setText('trend-total', `Total: ${fmtInt(totalEvents)}`);
    }

    function renderSessionBars(sessions, totalEvents) {
      const items = (sessions || []).slice(0, 8);
      const maxEvents = Math.max(...items.map((x) => x.events || 0), 1);
      const root = document.getElementById('session-bars');
      root.innerHTML = '';
      for (const item of items) {
        const pct = Math.max(2, Math.round(((item.events || 0) / maxEvents) * 100));
        const share = totalEvents > 0 ? ((item.events || 0) / totalEvents) * 100 : 0;
        const row = document.createElement('div');
        row.className = 'session-row';
        row.innerHTML = `
          <div>
            <div class="session-name">${esc(item.session)}</div>
            <div class="session-track"><div class="session-fill" style="width:${pct}%"></div></div>
          </div>
          <div class="session-val">${fmtPct(share)}</div>
        `;
        root.appendChild(row);
      }
    }

    function renderDerived(data) {
      const totals = data.totals || {};
      const days = Math.max(1, totals.days || 0);
      const sessions = Math.max(1, totals.sessions || 0);
      const events = totals.events || 0;
      const top = (data.top_sessions && data.top_sessions[0] && data.top_sessions[0].events) || 0;
      const events7d = (data.days || []).slice(0, 7).reduce((sum, x) => sum + (x.events || 0), 0);

      setText('events-per-day', fmtInt(Math.round(events / days)));
      setText('events-per-session', fmtInt(Math.round(events / sessions)));
      setText('top-share', fmtPct(events > 0 ? (top / events) * 100 : 0));
      setText('agent-count', fmtInt(Object.keys(data.agents || {}).length));
      setText('events-7d', fmtInt(events7d));
    }

    function renderSessions(sessions) {
      const tbody = document.querySelector('#sessions-table tbody');
      tbody.innerHTML = '';
      for (const item of sessions || []) {
        const tr = document.createElement('tr');
        tr.innerHTML = `<td>${esc(item.session)}</td><td>${esc(item.agent || 'unknown')}</td><td>${fmtInt(item.events)}</td><td>${fmtInt(item.days)}</td><td>${fmtInt(item.files)}</td><td>${esc(item.last_seen)}</td>`;
        tbody.appendChild(tr);
      }
    }

    function renderCosts(data) {
      if (!data || data.error) return;

      const total = data.total_cost_usd || 0;
      const codexCostTotal = data.codex_cost_total || 0;
      setText('cost-total', fmtCost(total));
      setText('codex-cost-total', fmtCost(codexCostTotal));
      setText('cost-combined', fmtCost(total + codexCostTotal));

      const codex = data.codex || {};
      setText('codex-cached', fmtInt(codex.cached_tokens));

      // Codex cost table
      const codexModels = data.codex_models || {};
      const codexCtbody = document.querySelector('#codex-cost-table tbody');
      codexCtbody.innerHTML = '';
      for (const [model, rec] of Object.entries(codexModels)) {
        const tr = document.createElement('tr');
        tr.innerHTML = `
          <td>${esc(model)}</td>
          <td>${fmtInt(rec.events)}</td>
          <td>${fmtInt(rec.input_tokens)}</td>
          <td>${fmtInt(rec.output_tokens)}</td>
          <td>${fmtInt(rec.cached_tokens)}</td>
          <td>${fmtInt(rec.reasoning_tokens)}</td>
          <td class="cost-highlight">${fmtCost(rec.cost_usd)}</td>
        `;
        codexCtbody.appendChild(tr);
      }
      if (Object.keys(codexModels).length > 1) {
        const totCost = Object.values(codexModels).reduce((s, r) => s + (r.cost_usd || 0), 0);
        const totEv = Object.values(codexModels).reduce((s, r) => s + (r.events || 0), 0);
        const totInp = Object.values(codexModels).reduce((s, r) => s + (r.input_tokens || 0), 0);
        const totOut = Object.values(codexModels).reduce((s, r) => s + (r.output_tokens || 0), 0);
        const totCached = Object.values(codexModels).reduce((s, r) => s + (r.cached_tokens || 0), 0);
        const totReas = Object.values(codexModels).reduce((s, r) => s + (r.reasoning_tokens || 0), 0);
        const tr = document.createElement('tr');
        tr.style.fontWeight = '700';
        tr.innerHTML = `<td>Total</td><td>${fmtInt(totEv)}</td><td>${fmtInt(totInp)}</td><td>${fmtInt(totOut)}</td><td>${fmtInt(totCached)}</td><td>${fmtInt(totReas)}</td><td class="cost-highlight">${fmtCost(totCost)}</td>`;
        codexCtbody.appendChild(tr);
      }

      const cursor = data.cursor || {};
      setText('cursor-tokens-total', fmtInt(cursor.total_tokens));

      // Claude cost table
      const tbody = document.querySelector('#cost-table tbody');
      tbody.innerHTML = '';
      for (const [model, rec] of Object.entries(data.claude || {})) {
        const tr = document.createElement('tr');
        tr.innerHTML = `
          <td>${esc(model)}</td>
          <td>${fmtInt(rec.events)}</td>
          <td>${fmtInt(rec.input_tokens)}</td>
          <td>${fmtInt(rec.output_tokens)}</td>
          <td>${fmtInt(rec.cache_read_tokens)}</td>
          <td>${fmtInt(rec.cache_write_tokens)}</td>
          <td class="cost-highlight">${fmtCost(rec.cost_usd)}</td>
        `;
        tbody.appendChild(tr);
      }
      // Totals row
      const claude = data.claude || {};
      const totInp = Object.values(claude).reduce((s, r) => s + (r.input_tokens || 0), 0);
      const totOut = Object.values(claude).reduce((s, r) => s + (r.output_tokens || 0), 0);
      const totCR  = Object.values(claude).reduce((s, r) => s + (r.cache_read_tokens || 0), 0);
      const totCW  = Object.values(claude).reduce((s, r) => s + (r.cache_write_tokens || 0), 0);
      const totEv  = Object.values(claude).reduce((s, r) => s + (r.events || 0), 0);
      if (Object.keys(claude).length > 1) {
        const tr = document.createElement('tr');
        tr.style.fontWeight = '700';
        tr.innerHTML = `<td>Total</td><td>${fmtInt(totEv)}</td><td>${fmtInt(totInp)}</td><td>${fmtInt(totOut)}</td><td>${fmtInt(totCR)}</td><td>${fmtInt(totCW)}</td><td class="cost-highlight">${fmtCost(total)}</td>`;
        tbody.appendChild(tr);
      }

      // Cursor table
      const ctbody = document.querySelector('#cursor-table tbody');
      ctbody.innerHTML = '';
      for (const [tool, tokens] of Object.entries(cursor.by_tool || {})) {
        const tr = document.createElement('tr');
        tr.innerHTML = `<td>${esc(tool)}</td><td>${fmtInt(tokens)}</td>`;
        ctbody.appendChild(tr);
      }

      // Activity — Claude Code
      const act = data.claude_activity || {};
      setText('claude-act-sessions', fmtInt(act.sessions));
      setText('claude-act-tools', fmtInt(act.total_tool_calls));
      setText('claude-act-agents', fmtInt(act.agent_dispatches));
      setText('claude-act-sidechain', fmtInt(act.sidechain_events));

      const toolsTbody = document.querySelector('#claude-tools-table tbody');
      toolsTbody.innerHTML = '';
      for (const [tool, n] of Object.entries(act.tools || {})) {
        const tr = document.createElement('tr');
        tr.innerHTML = `<td>${esc(tool)}</td><td>${fmtInt(n)}</td>`;
        toolsTbody.appendChild(tr);
      }

      const agentsTbody = document.querySelector('#claude-agents-table tbody');
      agentsTbody.innerHTML = '';
      for (const [atype, n] of Object.entries(act.agents || {})) {
        const tr = document.createElement('tr');
        tr.innerHTML = `<td>${esc(atype)}</td><td>${fmtInt(n)}</td>`;
        agentsTbody.appendChild(tr);
      }

      // Activity — Codex
      setText('codex-act-sessions', fmtInt(codex.sessions));
      setText('codex-act-tasks', fmtInt(codex.tasks));
      setText('codex-act-plans', fmtInt(codex.plans));
      setText('codex-act-msgs', fmtInt(codex.agent_messages));

      // Other tools
      const copilot = data.copilot || {};
      const el = document.getElementById('other-tools-stats');
      el.innerHTML = `
        <div><strong>Copilot</strong> — ${fmtInt(copilot.sessions)} sessions, ${fmtInt(copilot.tool_calls)} tool calls</div>
        <div style="margin-top:8px;color:var(--muted);font-size:11px">Cursor costs not calculable — model not logged. Copilot costs not calculable — no token counts in session-state logs.</div>
      `;

      const note = document.getElementById('pricing-note');
      if (data.pricing_loaded) {
        note.textContent = `Pricing: pydantic/genai-prices (${data.pricing_model_count} models loaded).`;
      } else {
        note.textContent = 'Pricing data unavailable — check network or ~/.cache/genai-prices-slim.json.';
        note.style.color = 'var(--warn)';
      }
    }

    async function refreshSummary() {
      try {
        const response = await fetch('/api/summary', { cache: 'no-store' });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const data = await response.json();

        setText('sub', `Root: ${data.root}`);
        setText('header-meta', `Refresh ${Math.floor(REFRESH_MS / 1000)}s`);
        setText('events', fmtInt(data.totals.events));
        setText('sessions', fmtInt(data.totals.sessions));
        setText('days', fmtInt(data.totals.days));
        setText('files', fmtInt(data.totals.files));
        setText('bytes', fmtBytes(data.totals.bytes));

        renderDays(data.days || []);
        renderAgents(data.agents || {});
        renderTrend(data.days || []);
        renderSessionBars(data.top_sessions || [], data.totals.events || 0);
        renderSessions(data.top_sessions || []);
        renderDerived(data);

        const newest = data.totals.newest_file_mtime || 'n/a';
        setText('foot', `Updated ${shortTs(data.generated_at)}. Newest file mtime: ${shortTs(newest)}.`);
      } catch (err) {
        setText('sub', `Failed to load data: ${String(err)}`);
      }
    }

    async function refreshCosts() {
      try {
        const response = await fetch('/api/costs', { cache: 'no-store' });
        if (!response.ok) return;
        renderCosts(await response.json());
      } catch (_) {}
    }

    function renderPipeline(data) {
      if (!data) return;

      const online = data.online;
      const statusEl = document.getElementById('pipeline-status');
      statusEl.textContent = online ? 'Online' : ('Offline' + (data.error ? ': ' + data.error : ''));
      statusEl.style.color = online ? 'var(--good)' : 'var(--warn)';

      if (!online) return;

      const components = data.components || [];
      const sources = components.filter(c => c.kind === 'source');
      const transforms = components.filter(c => c.kind === 'transform');

      setText('pipeline-sources', fmtInt(sources.length));
      setText('pipeline-transforms', fmtInt(transforms.length));
      setText('pipeline-events', fmtInt(data.total_events));
      setText('pipeline-bytes', fmtBytes(data.total_bytes));

      const tbody = document.querySelector('#pipeline-table tbody');
      tbody.innerHTML = '';

      // Sort: sources first, then transforms, then sinks; within kind by events desc
      const order = { source: 0, transform: 1, sink: 2 };
      const sorted = [...components].sort((a, b) =>
        (order[a.kind] - order[b.kind]) || (b.events - a.events)
      );

      const kindColors = { source: 'var(--accent)', transform: 'var(--warn)', sink: 'var(--good)' };
      for (const c of sorted) {
        const tr = document.createElement('tr');
        const kindBadge = `<span style="font-size:10px;color:${kindColors[c.kind] || 'var(--muted)'}">${esc(c.kind)}</span>`;
        tr.innerHTML = `<td>${esc(c.id)}</td><td>${kindBadge}</td><td>${fmtInt(c.events)}</td><td>${c.bytes ? fmtBytes(c.bytes) : '-'}</td>`;
        tbody.appendChild(tr);
      }
    }

    async function refreshPipeline() {
      try {
        const response = await fetch('/api/pipeline', { cache: 'no-store' });
        if (!response.ok) return;
        renderPipeline(await response.json());
      } catch (_) {}
    }

    refreshSummary();
    refreshCosts();
    refreshPipeline();
    setInterval(refreshSummary, REFRESH_MS);
    setInterval(refreshCosts, REFRESH_MS * 2);
    setInterval(refreshPipeline, REFRESH_MS * 2);
  </script>
</body>
</html>
"""


def make_handler(state: DashboardState, refresh_ms: int):
    html = HTML_TEMPLATE.replace("REFRESH_MS_PLACEHOLDER", str(refresh_ms))

    class Handler(BaseHTTPRequestHandler):
        def _send(self, code: int, body: bytes, content_type: str) -> None:
            self.send_response(code)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format: str, *args) -> None:  # noqa: A002
            return

        def do_GET(self) -> None:  # noqa: N802
            if self.path in ("/", "/index.html"):
                self._send(HTTPStatus.OK, html.encode("utf-8"), "text/html; charset=utf-8")
                return

            if self.path == "/api/summary":
                payload = json.dumps(state.get_summary()).encode("utf-8")
                self._send(HTTPStatus.OK, payload, "application/json; charset=utf-8")
                return

            if self.path == "/api/costs":
                payload = json.dumps(state.get_costs()).encode("utf-8")
                self._send(HTTPStatus.OK, payload, "application/json; charset=utf-8")
                return

            if self.path == "/api/pipeline":
                payload = json.dumps(state.get_pipeline()).encode("utf-8")
                self._send(HTTPStatus.OK, payload, "application/json; charset=utf-8")
                return

            if self.path == "/healthz":
                payload = json.dumps({"ok": True, "time": now_iso()}).encode("utf-8")
                self._send(HTTPStatus.OK, payload, "application/json; charset=utf-8")
                return

            self._send(HTTPStatus.NOT_FOUND, b"not found", "text/plain; charset=utf-8")

    return Handler


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Serve centralized AI logs dashboard with token cost analysis"
    )
    parser.add_argument(
        "--root",
        default=os.path.expanduser("~/logs/ai"),
        help="Centralized logs root path (default: ~/logs/ai)",
    )
    parser.add_argument(
        "--vector-root",
        default=os.path.expanduser("~/logs/ai/vector"),
        help="Vector sink directory for cost analysis (default: ~/logs/ai/vector)",
    )
    parser.add_argument(
        "--host", default="127.0.0.1", help="Bind host (default: 127.0.0.1)"
    )
    parser.add_argument(
        "--port", type=int, default=8765, help="Bind port (default: 8765)"
    )
    parser.add_argument(
        "--refresh-seconds",
        type=int,
        default=10,
        help="How often browser refreshes data (default: 10)",
    )
    parser.add_argument(
        "--cache-seconds",
        type=int,
        default=5,
        help="Server summary cache duration in seconds (default: 5)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).expanduser().resolve()
    vector_root = Path(args.vector_root).expanduser().resolve()
    state = DashboardState(
        root=root,
        vector_root=vector_root,
        cache_ttl=max(args.cache_seconds, 1),
    )
    handler = make_handler(state, refresh_ms=max(args.refresh_seconds, 1) * 1000)

    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"AI logs dashboard: http://{args.host}:{args.port}")
    print(f"Log root:    {root}")
    print(f"Vector root: {vector_root}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
