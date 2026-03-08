#!/usr/bin/env python3
"""Query and analyse Claude Code session data from Vector JSONL shards.

Usage:
  claude-sessions.py sessions              # list all sessions with stats
  claude-sessions.py tools                 # tool call frequency across all sessions
  claude-sessions.py agents                # subagent dispatch breakdown by type
  claude-sessions.py tree <session-id>     # print tool/subagent tree for one session
  claude-sessions.py show <session-id>     # full turn-by-turn timeline for a session
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

@dataclass
class ToolCall:
    id: str           # toolu_... (matches toolUseID on progress events)
    name: str
    input: dict
    uuid: str         # event uuid — matches parentUuid on sidechain events
    timestamp: str
    is_sidechain: bool
    session_file: str


@dataclass
class Session:
    session_id: str                      # shared between parent + sidechains
    files: set[str] = field(default_factory=set)   # JSONL file UUIDs contributing
    cwd: str = ""
    slug: str = ""
    git_branch: str = ""
    first_ts: str = ""
    last_ts: str = ""
    version: str = ""
    events: list[dict] = field(default_factory=list)
    tool_calls: list[ToolCall] = field(default_factory=list)
    # subagent linkage
    agent_dispatches: list[dict] = field(default_factory=list)  # Agent tool_use inputs
    sidechain_events: list[dict] = field(default_factory=list)
    # token totals
    input_tokens: int = 0
    output_tokens: int = 0
    cache_read_tokens: int = 0
    cache_write_tokens: int = 0

    def is_sidechain_only(self) -> bool:
        return all(e.get("isSidechain") for e in self.events if e.get("type") == "assistant")


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

def open_shard(path: Path):
    if path.suffix == ".gz":
        return gzip.open(path, "rt", encoding="utf-8", errors="ignore")
    return path.open("rt", encoding="utf-8", errors="ignore")


def iter_claude_events(vector_root: Path) -> Iterator[dict]:
    for shard in sorted(vector_root.glob("*.jsonl*")):
        with open_shard(shard) as f:
            for line in f:
                try:
                    e = json.loads(line)
                except Exception:
                    continue
                if e.get("source") == "claude-code":
                    yield e


def load_sessions(vector_root: Path) -> dict[str, Session]:
    sessions: dict[str, Session] = {}

    for e in iter_claude_events(vector_root):
        sid = e.get("sessionId") or e.get("session") or ""
        if not sid:
            continue

        if sid not in sessions:
            sessions[sid] = Session(session_id=sid)

        s = sessions[sid]
        s.files.add(e.get("session") or "")

        raw_ts = e.get("timestamp", "")
        if isinstance(raw_ts, int):
            # millisecond epoch → ISO string for consistent comparison
            ts = datetime.fromtimestamp(raw_ts / 1000, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
        else:
            ts = str(raw_ts) if raw_ts else ""
        if ts:
            if not s.first_ts or ts < s.first_ts:
                s.first_ts = ts
            if ts > s.last_ts:
                s.last_ts = ts

        if not s.cwd and e.get("cwd"):
            s.cwd = e["cwd"]
        if not s.slug and e.get("slug"):
            s.slug = e["slug"]
        if not s.git_branch and e.get("gitBranch"):
            s.git_branch = e["gitBranch"]
        if not s.version and e.get("version"):
            s.version = e["version"]

        s.events.append(e)

        if e.get("type") == "assistant":
            msg = e.get("message") or {}
            usage = msg.get("usage") or {}
            s.input_tokens += usage.get("input_tokens") or 0
            s.output_tokens += usage.get("output_tokens") or 0
            s.cache_read_tokens += usage.get("cache_read_input_tokens") or 0
            s.cache_write_tokens += usage.get("cache_creation_input_tokens") or 0

            content = msg.get("content") or []
            for block in (content if isinstance(content, list) else []):
                if not isinstance(block, dict) or block.get("type") != "tool_use":
                    continue
                tc = ToolCall(
                    id=block.get("id", ""),
                    name=block.get("name", "?"),
                    input=block.get("input") or {},
                    uuid=e.get("uuid", ""),
                    timestamp=ts,
                    is_sidechain=bool(e.get("isSidechain")),
                    session_file=e.get("session", ""),
                )
                s.tool_calls.append(tc)
                if block.get("name") == "Agent":
                    s.agent_dispatches.append({
                        "uuid": e.get("uuid", ""),
                        "tool_id": block.get("id", ""),
                        "subagent_type": block.get("input", {}).get("subagent_type", "?"),
                        "description": block.get("input", {}).get("description", ""),
                        "model": block.get("input", {}).get("model", ""),
                        "timestamp": ts,
                        "is_sidechain": bool(e.get("isSidechain")),
                    })

        if e.get("isSidechain"):
            s.sidechain_events.append(e)

    return sessions


# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------

def short_ts(iso: str) -> str:
    if not iso:
        return "n/a"
    return iso[:16].replace("T", " ")


def short_id(s: str) -> str:
    return s[:8] if s else "?"


def fmt_tokens(n: int) -> str:
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n/1_000:.0f}K"
    return str(n)


def short_path(p: str) -> str:
    home = os.environ.get("HOME", "")
    if home and p.startswith(home):
        return "~" + p[len(home):]
    return p


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_sessions(sessions: dict[str, Session], args) -> None:
    rows = sorted(sessions.values(), key=lambda s: s.last_ts, reverse=True)

    limit = getattr(args, "limit", 30)
    if limit:
        rows = rows[:limit]

    print(f"{'SESSION':>8}  {'SLUG':<28}  {'TOOLS':>5}  {'AGENTS':>6}  {'IN':>7}  {'OUT':>7}  {'CR':>7}  {'FIRST':<16}  {'CWD'}")
    print("-" * 130)
    for s in rows:
        main_tools = sum(1 for tc in s.tool_calls if not tc.is_sidechain)
        side_tools = sum(1 for tc in s.tool_calls if tc.is_sidechain)
        tool_str = f"{main_tools}" if not side_tools else f"{main_tools}+{side_tools}s"
        print(
            f"{short_id(s.session_id):>8}  "
            f"{s.slug[:28]:<28}  "
            f"{tool_str:>5}  "
            f"{len(s.agent_dispatches):>6}  "
            f"{fmt_tokens(s.input_tokens):>7}  "
            f"{fmt_tokens(s.output_tokens):>7}  "
            f"{fmt_tokens(s.cache_read_tokens):>7}  "
            f"{short_ts(s.first_ts):<16}  "
            f"{short_path(s.cwd)}"
        )
    print(f"\n{len(sessions)} total sessions")


def cmd_tools(sessions: dict[str, Session], args) -> None:
    from collections import Counter
    counts: Counter = Counter()
    sidechain_counts: Counter = Counter()
    for s in sessions.values():
        for tc in s.tool_calls:
            if tc.is_sidechain:
                sidechain_counts[tc.name] += 1
            else:
                counts[tc.name] += 1

    all_tools = set(counts) | set(sidechain_counts)
    rows = sorted(all_tools, key=lambda t: -(counts[t] + sidechain_counts[t]))

    print(f"{'TOOL':<30}  {'MAIN':>6}  {'SIDECHAIN':>9}  {'TOTAL':>6}")
    print("-" * 60)
    for tool in rows:
        m, sc = counts[tool], sidechain_counts[tool]
        print(f"{tool:<30}  {m:>6}  {sc:>9}  {m+sc:>6}")
    print(f"\n{sum(counts.values())} main + {sum(sidechain_counts.values())} sidechain tool calls")


def cmd_agents(sessions: dict[str, Session], args) -> None:
    from collections import Counter
    by_type: Counter = Counter()
    by_session: dict[str, list] = defaultdict(list)

    for s in sessions.values():
        for d in s.agent_dispatches:
            t = d["subagent_type"]
            by_type[t] += 1
            by_session[t].append({
                "session": short_id(s.session_id),
                "slug": s.slug,
                "desc": d["description"][:60],
                "ts": short_ts(d["timestamp"]),
                "model": d.get("model", ""),
            })

    print(f"{'SUBAGENT TYPE':<40}  {'COUNT':>5}")
    print("-" * 50)
    for t, n in by_type.most_common():
        print(f"{t:<40}  {n:>5}")

    if getattr(args, "detail", False):
        print()
        for t, n in by_type.most_common():
            print(f"\n── {t} ({n} dispatches) ──")
            for row in by_session[t][:10]:
                print(f"  [{row['ts']}] {row['session']} {row['slug'][:20]}")
                if row["desc"]:
                    print(f"    {row['desc']}")


def cmd_tree(sessions: dict[str, Session], args) -> None:
    target = args.session_id

    # Match by prefix or full id
    matches = [s for sid, s in sessions.items() if sid.startswith(target) or s.slug == target]
    if not matches:
        print(f"No session matching '{target}'", file=sys.stderr)
        sys.exit(1)
    if len(matches) > 1:
        print(f"Ambiguous: {len(matches)} sessions match '{target}':", file=sys.stderr)
        for m in matches:
            print(f"  {m.session_id}  {m.slug}", file=sys.stderr)
        sys.exit(1)

    s = matches[0]
    print(f"Session: {s.session_id}")
    print(f"  slug:    {s.slug}")
    print(f"  cwd:     {short_path(s.cwd)}")
    print(f"  branch:  {s.git_branch}")
    print(f"  period:  {short_ts(s.first_ts)} → {short_ts(s.last_ts)}")
    print(f"  tokens:  in={fmt_tokens(s.input_tokens)} out={fmt_tokens(s.output_tokens)} cache_read={fmt_tokens(s.cache_read_tokens)}")
    print()

    # Build uuid → tool call map for linking sidechain events
    uuid_to_dispatch = {d["uuid"]: d for d in s.agent_dispatches}

    # Group sidechain events by their parentUuid (= Agent tool_use event uuid)
    sidechain_by_parent: dict[str, list[dict]] = defaultdict(list)
    for e in s.sidechain_events:
        sidechain_by_parent[e.get("parentUuid", "")].append(e)

    # Print main tool call timeline, expanding Agent calls inline
    print("Main timeline (sorted by time):")
    main_calls = sorted(
        [tc for tc in s.tool_calls if not tc.is_sidechain],
        key=lambda tc: tc.timestamp,
    )
    for tc in main_calls:
        print(f"  [{short_ts(tc.timestamp)}] {tc.name}")
        if tc.name == "Agent":
            dispatch = {d["uuid"]: d for d in s.agent_dispatches}.get(tc.uuid, {})
            agent_type = dispatch.get("subagent_type", "?")
            desc = dispatch.get("description", "")
            model = dispatch.get("model", "")
            model_str = f" [{model}]" if model else ""
            print(f"    └─ subagent_type: {agent_type}{model_str}")
            if desc:
                print(f"       desc: {desc[:80]}")
            child_events = sidechain_by_parent.get(tc.uuid, [])
            child_tools: list[str] = []
            for ce in child_events:
                if ce.get("type") == "assistant":
                    msg = ce.get("message") or {}
                    for block in (msg.get("content") or []):
                        if isinstance(block, dict) and block.get("type") == "tool_use":
                            child_tools.append(block.get("name", "?"))
            if child_tools:
                from collections import Counter
                counts = Counter(child_tools)
                summary = ", ".join(f"{n}×{k}" for k, n in counts.most_common(6))
                print(f"       tools: {summary}")

    print()
    # Summary
    from collections import Counter
    tool_counts = Counter(tc.name for tc in s.tool_calls if not tc.is_sidechain)
    print(f"Main tool counts: {dict(tool_counts.most_common(10))}")
    print(f"Agent dispatches: {len(s.agent_dispatches)}")
    sidechain_tool_counts = Counter(tc.name for tc in s.tool_calls if tc.is_sidechain)
    if sidechain_tool_counts:
        print(f"Sidechain tool counts: {dict(sidechain_tool_counts.most_common(10))}")


def cmd_show(sessions: dict[str, Session], args) -> None:
    target = args.session_id
    matches = [s for sid, s in sessions.items() if sid.startswith(target) or s.slug == target]
    if not matches:
        print(f"No session matching '{target}'", file=sys.stderr)
        sys.exit(1)
    s = matches[0]

    events = sorted(s.events, key=lambda e: e.get("timestamp", ""))
    for e in events:
        ts = short_ts(e.get("timestamp", ""))
        t = e.get("type", "?")
        side = " [sidechain]" if e.get("isSidechain") else ""
        prefix = f"[{ts}] {t:<20}{side}"

        if t == "user":
            msg = e.get("message") or {}
            content = msg.get("content") or "" if isinstance(msg, dict) else ""
            if isinstance(content, list):
                text = " ".join(b.get("text","") for b in content if isinstance(b,dict) and b.get("type")=="text")
            else:
                text = str(content)
            print(f"{prefix}  {text[:100]}")

        elif t == "assistant":
            msg = e.get("message") or {}
            tools = []
            for block in (msg.get("content") or [] if isinstance(msg,dict) else []):
                if isinstance(block, dict) and block.get("type") == "tool_use":
                    name = block.get("name","?")
                    if name == "Agent":
                        st = (block.get("input") or {}).get("subagent_type","?")
                        tools.append(f"Agent({st})")
                    else:
                        tools.append(name)
            usage = (msg.get("usage") or {}) if isinstance(msg,dict) else {}
            tok = f"in={usage.get('input_tokens',0)} out={usage.get('output_tokens',0)}"
            print(f"{prefix}  tools=[{', '.join(tools)}]  {tok}")

        elif t == "progress":
            tool_id = e.get("toolUseID","")[:12]
            print(f"{prefix}  toolUseID={tool_id}")

        else:
            print(prefix)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description="Analyse Claude Code sessions from Vector logs")
    parser.add_argument(
        "--vector-root",
        default=os.path.expanduser("~/logs/ai/vector"),
        help="Vector JSONL shard directory",
    )
    sub = parser.add_subparsers(dest="command")

    p_sessions = sub.add_parser("sessions", help="List sessions with stats")
    p_sessions.add_argument("--limit", type=int, default=30)

    sub.add_parser("tools", help="Tool call frequency")

    p_agents = sub.add_parser("agents", help="Subagent dispatch breakdown")
    p_agents.add_argument("--detail", action="store_true")

    p_tree = sub.add_parser("tree", help="Tool/subagent tree for a session")
    p_tree.add_argument("session_id")

    p_show = sub.add_parser("show", help="Turn-by-turn timeline for a session")
    p_show.add_argument("session_id")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        return 1

    vector_root = Path(args.vector_root)
    if not vector_root.exists():
        print(f"Vector root not found: {vector_root}", file=sys.stderr)
        return 1

    sessions = load_sessions(vector_root)

    dispatch = {
        "sessions": cmd_sessions,
        "tools": cmd_tools,
        "agents": cmd_agents,
        "tree": cmd_tree,
        "show": cmd_show,
    }
    dispatch[args.command](sessions, args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
