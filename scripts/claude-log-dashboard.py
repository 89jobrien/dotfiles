#!/usr/bin/env python3
"""Serve a lightweight dashboard for centralized AI CLI logs."""

from __future__ import annotations

import argparse
import gzip
import json
import os
import re
import threading
import time
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Dict, Iterable, List, Tuple


DAY_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


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


@dataclass
class DashboardState:
    root: Path
    cache_ttl: int
    _lock: threading.Lock = field(default_factory=threading.Lock)
    _cached_at: float = 0.0
    _cached_summary: Dict | None = None

    def get_summary(self) -> Dict:
        with self._lock:
            now = time.time()
            if self._cached_summary and (now - self._cached_at) < self.cache_ttl:
                return self._cached_summary
            summary = build_summary(self.root)
            self._cached_summary = summary
            self._cached_at = now
            return summary


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

        # Legacy layout: json/text subdirectories
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

    # New layout: root/<tool>/<day>/<session>/events.jsonl
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
            # Legacy flat layout: root/<day>/<session>/events.jsonl
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

    .kpi-grid {
      display: grid;
      grid-template-columns: repeat(10, minmax(0, 1fr));
      gap: 8px;
      margin-bottom: 10px;
    }

    @media (max-width: 1240px) {
      .kpi-grid { grid-template-columns: repeat(5, minmax(0, 1fr)); }
    }

    @media (max-width: 740px) {
      .kpi-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
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
    }

    .foot {
      margin-top: 4px;
      color: var(--muted);
      font-size: 11px;
    }

    @keyframes card-enter {
      from {
        opacity: 0;
        transform: translateY(6px);
      }
      to {
        opacity: 1;
        transform: translateY(0);
      }
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
      let i = 0;
      let n = bytes;
      while (n >= 1024 && i < units.length - 1) {
        n /= 1024;
        i += 1;
      }
      return `${n.toFixed(n >= 10 || i === 0 ? 0 : 1)} ${units[i]}`;
    }

    function fmtPct(value) {
      if (!Number.isFinite(value)) return '0.0%';
      return `${value.toFixed(1)}%`;
    }

    function shortTs(value) {
      if (!value) return 'n/a';
      const d = new Date(value);
      if (Number.isNaN(d.getTime())) return value;
      return d.toISOString().replace('T', ' ').slice(0, 16) + 'Z';
    }

    function setText(id, text) {
      document.getElementById(id).textContent = text;
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

    const AGENT_COLORS = { claude: '#4da3ff', codex: '#f9b266', opencode: '#4bc08c', gemini: '#c084fc' };

    function renderAgents(tools) {
      const entries = Object.entries(tools || {}).map(([name, rec]) => ({ name, events: rec.events || 0 }));
      entries.sort((a, b) => b.events - a.events);
      const total = entries.reduce((sum, item) => sum + item.events, 0);

      // Build conic gradient from tool slices
      const donut = document.getElementById('agents-donut');
      let gradParts = [];
      let cursor = 0;
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
        const pct = total > 0 ? ((item.events / total) * 100) : 0;
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
      const agentCount = Object.keys(data.tools || {}).length;
      const events7d = (data.days || []).slice(0, 7).reduce((sum, x) => sum + (x.events || 0), 0);

      setText('events-per-day', fmtInt(Math.round(events / days)));
      setText('events-per-session', fmtInt(Math.round(events / sessions)));
      setText('top-share', fmtPct(events > 0 ? (top / events) * 100 : 0));
      setText('agent-count', fmtInt(agentCount));
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

    async function refresh() {
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
        renderAgents(data.tools || {});
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

    refresh();
    setInterval(refresh, REFRESH_MS);
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
                self._send(
                    HTTPStatus.OK, html.encode("utf-8"), "text/html; charset=utf-8"
                )
                return

            if self.path == "/api/summary":
                payload = json.dumps(state.get_summary()).encode("utf-8")
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
        description="Serve centralized Claude logs dashboard"
    )
    parser.add_argument(
        "--root",
        default=os.path.expanduser("~/logs/ai"),
        help="Centralized logs root path (default: ~/logs/ai)",
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
    state = DashboardState(root=root, cache_ttl=max(args.cache_seconds, 1))
    handler = make_handler(state, refresh_ms=max(args.refresh_seconds, 1) * 1000)

    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"AI logs dashboard: http://{args.host}:{args.port}")
    print(f"Log root: {root}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
