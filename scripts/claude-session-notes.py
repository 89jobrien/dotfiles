#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Generate Obsidian notes from Claude Code session JSONL files.

Usage:
  claude-session-notes.py [--vault PATH] [--out-dir PATH] [--session ID] [--dry-run]
"""

import json
import os
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path
from typing import Optional


VAULT_DEFAULT = Path.home() / "Documents" / "Obsidian Vault"
OUT_DIR_DEFAULT = "03_Area-Systems/claude-sessions"

# Map CWD patterns to project wikilinks
CWD_TO_PROJECT = {
    "dotfiles": "dotfiles",
    "devloop": "devloop",
    "minibox": "minibox",
    "devkit": "devkit",
    "doob": "doob",
    "maestro": "maestro",
    "personal-mcp": "personal-mcp",
    "obfsck": "obfsck",
    "tools": "tools",
    "braid": "braid",
    "pieces-ob": "pieces-ob",
    "obsidian": "obsidian-vault",
    "Obsidian": "obsidian-vault",
}


def cwd_to_wikilink(cwd: str) -> Optional[str]:
    for pattern, link in CWD_TO_PROJECT.items():
        if pattern in cwd:
            return link
    return None


def project_slug_from_path(path: Path) -> str:
    """Convert ~/.claude/projects/-Users-joe-dev-devloop/... to devloop"""
    name = path.parent.name
    # Remove leading -Users-joe- prefix variations
    name = re.sub(r"^-Users-[^-]+-", "", name)
    name = re.sub(r"^-Users-[^-]+", "", name)
    name = name.lstrip("-")
    # Strip dev- prefix
    name = re.sub(r"^dev-", "", name)
    return name or path.parent.name


def parse_session(jsonl_path: Path) -> dict:
    """Extract structured data from a session JSONL file."""
    session_id = jsonl_path.stem[:8]
    full_id = jsonl_path.stem

    events = []
    with open(jsonl_path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                continue

    if not events:
        return {}

    # Basic metadata — scan for first non-empty slug and cwd
    cwd = "~"
    slug = ""
    session_start = ""
    session_end = ""
    for e in events:
        if not cwd or cwd == "~":
            cwd = e.get("cwd", "~") or "~"
        if not slug:
            slug = e.get("slug", "") or ""
        if not session_start:
            session_start = e.get("timestamp", "")[:16].replace("T", " ")
    if events:
        session_end = events[-1].get("timestamp", "")[:16].replace("T", " ")

    # Separate main chain from sidechain
    main_events = [e for e in events if not e.get("isSidechain")]
    side_events = [e for e in events if e.get("isSidechain")]

    # Tool call counts
    main_tools: Counter = Counter()
    side_tools: Counter = Counter()
    agent_dispatches: list[dict] = []
    user_messages: list[str] = []
    assistant_texts: list[str] = []

    for e in main_events:
        msg = e.get("message", {})
        role = msg.get("role")
        content = msg.get("content", [])

        if role == "user" and isinstance(content, list):
            for c in content:
                if isinstance(c, dict) and c.get("type") == "human":
                    txt = c.get("text", "").strip()
                    if txt and len(txt) > 2:
                        user_messages.append(txt[:300])

        if role == "assistant" and isinstance(content, list):
            for c in content:
                if isinstance(c, dict):
                    if c.get("type") == "tool_use":
                        name = c.get("name", "")
                        main_tools[name] += 1
                        if name == "Agent":
                            inp = c.get("input", {})
                            agent_dispatches.append({
                                "ts": e.get("timestamp", "")[:16].replace("T", " "),
                                "desc": inp.get("description", ""),
                                "type": inp.get("subagent_type", ""),
                            })
                    elif c.get("type") == "text":
                        txt = c.get("text", "").strip()
                        if txt and len(txt) > 20:
                            assistant_texts.append(txt)

    for e in side_events:
        msg = e.get("message", {})
        role = msg.get("role")
        content = msg.get("content", [])
        if role == "assistant" and isinstance(content, list):
            for c in content:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    side_tools[c.get("name", "")] += 1

    # Token counts — sum across all main-chain assistant messages
    input_tokens = 0
    output_tokens = 0
    cache_tokens = 0
    for e in events:
        if e.get("isSidechain"):
            continue
        msg = e.get("message", {})
        if msg.get("role") != "assistant":
            continue
        usage = msg.get("usage")
        if usage:
            input_tokens += usage.get("input_tokens", 0)
            output_tokens += usage.get("output_tokens", 0)
            cache_tokens += usage.get("cache_read_input_tokens", 0)

    # Infer project from CWD
    project_link = cwd_to_wikilink(cwd)
    project_slug = project_slug_from_path(jsonl_path)

    # Theme: first ~2 assistant sentences
    theme = ""
    if assistant_texts:
        first_text = assistant_texts[0]
        sentences = re.split(r'(?<=[.!?])\s+', first_text)
        theme = " ".join(sentences[:2])[:400]

    # Summarize what was worked on from user messages + assistant opening texts
    topics = extract_topics(user_messages, assistant_texts)

    return {
        "session_id": full_id,
        "short_id": session_id,
        "slug": slug,
        "cwd": cwd,
        "project_link": project_link,
        "project_slug": project_slug,
        "start": session_start,
        "end": session_end,
        "main_tools": main_tools,
        "side_tools": side_tools,
        "agent_dispatches": agent_dispatches,
        "user_messages": user_messages,
        "assistant_texts": assistant_texts,
        "theme": theme,
        "topics": topics,
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "cache_tokens": cache_tokens,
    }


def extract_topics(user_msgs: list[str], assistant_texts: list[str]) -> list[str]:
    """Heuristically extract key topics from the session."""
    topics = []

    # Look for imperative phrases in user messages
    for msg in user_msgs[:20]:
        msg = msg.strip()
        if len(msg) < 5:
            continue
        # Short user messages are often commands/topics
        if len(msg) < 120:
            topics.append(msg)

    # Also grab first line of early assistant messages (these often describe what's happening)
    for text in assistant_texts[:5]:
        first_line = text.split("\n")[0].strip()
        if 10 < len(first_line) < 200:
            topics.append(first_line)

    # Deduplicate while preserving order
    seen = set()
    result = []
    for t in topics:
        key = t.lower()[:60]
        if key not in seen:
            seen.add(key)
            result.append(t)
    return result[:10]


def fmt_tokens(n: int) -> str:
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n/1_000:.1f}K"
    return str(n)


def render_note(s: dict) -> str:
    slug = s["slug"] or s["short_id"]
    project_link = s["project_link"]
    project_tag = s["project_slug"].replace("-", "_")

    tags = ["claude-session"]
    if project_tag:
        tags.append(f"project/{project_tag}")

    # YAML frontmatter
    lines = [
        "---",
        f"type: claude-session",
        f"session_id: {s['session_id']}",
        f"slug: {slug}",
        f"date: {s['start'][:10]}",
        f"cwd: {s['cwd']}",
    ]
    if project_link:
        lines.append(f"project: \"[[{project_link}]]\"")
    lines += [
        f"tags: [{', '.join(tags)}]",
        f"tools_main: {sum(s['main_tools'].values())}",
        f"tools_side: {sum(s['side_tools'].values())}",
        f"agents: {len(s['agent_dispatches'])}",
        f"tokens_in: {fmt_tokens(s['input_tokens'])}",
        f"tokens_out: {fmt_tokens(s['output_tokens'])}",
        "---",
        "",
    ]

    # Title
    lines.append(f"# {slug}")
    lines.append("")
    lines.append(f"**{s['start']} → {s['end']}**  ")
    lines.append(f"CWD: `{s['cwd']}`" + (f"  |  Project: [[{project_link}]]" if project_link else ""))
    lines.append("")

    # Stats bar
    main_total = sum(s['main_tools'].values())
    side_total = sum(s['side_tools'].values())
    lines.append("## Stats")
    lines.append("")
    lines.append(f"| Metric | Value |")
    lines.append(f"|--------|-------|")
    lines.append(f"| Tool calls (main) | {main_total} |")
    lines.append(f"| Tool calls (sidechain) | {side_total} |")
    lines.append(f"| Agent dispatches | {len(s['agent_dispatches'])} |")
    lines.append(f"| Input tokens | {fmt_tokens(s['input_tokens'])} |")
    lines.append(f"| Output tokens | {fmt_tokens(s['output_tokens'])} |")
    lines.append("")

    # Top tools
    if s['main_tools']:
        lines.append("## Top Tools (main chain)")
        lines.append("")
        for tool, count in s['main_tools'].most_common(8):
            lines.append(f"- `{tool}`: {count}")
        lines.append("")

    # Agent dispatches
    if s['agent_dispatches']:
        lines.append("## Agent Dispatches")
        lines.append("")
        for a in s['agent_dispatches']:
            atype = a['type'] or '?'
            desc = a['desc'] or '(no description)'
            lines.append(f"- `{atype}` — {desc}")
        lines.append("")

    # User messages / conversation flow
    if s['user_messages']:
        lines.append("## Conversation")
        lines.append("")
        for msg in s['user_messages'][:15]:
            msg = msg.replace('\n', ' ').strip()
            lines.append(f"> {msg}")
            lines.append("")

    # Topics / key themes
    if s['topics']:
        lines.append("## Key Topics")
        lines.append("")
        for t in s['topics']:
            t = t.replace('\n', ' ').strip()
            lines.append(f"- {t}")
        lines.append("")

    # Opening assistant context
    if s['assistant_texts']:
        lines.append("## Opening Context")
        lines.append("")
        first = s['assistant_texts'][0][:600].replace('\n', '\n> ')
        lines.append(f"> {first}")
        lines.append("")

    return "\n".join(lines)


def find_all_sessions(projects_dir: Path) -> list[Path]:
    """Find all session JSONL files."""
    paths = []
    for jsonl in projects_dir.rglob("*.jsonl"):
        if jsonl.parent.name == "memory":
            continue
        if jsonl.name == "MEMORY.md":
            continue
        paths.append(jsonl)
    return sorted(paths, key=lambda p: p.stat().st_mtime, reverse=True)


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Generate Obsidian notes from Claude sessions")
    parser.add_argument("--vault", default=str(VAULT_DEFAULT), help="Obsidian vault path")
    parser.add_argument("--out-dir", default=OUT_DIR_DEFAULT, help="Output directory relative to vault")
    parser.add_argument("--session", help="Only process this session ID prefix")
    parser.add_argument("--dry-run", action="store_true", help="Print notes without writing")
    args = parser.parse_args()

    vault = Path(args.vault)
    out_dir = vault / args.out_dir
    projects_dir = Path.home() / ".claude" / "projects"

    if not args.dry_run:
        out_dir.mkdir(parents=True, exist_ok=True)

    all_sessions = find_all_sessions(projects_dir)
    if args.session:
        all_sessions = [p for p in all_sessions if p.stem.startswith(args.session)]

    print(f"Found {len(all_sessions)} session files", file=sys.stderr)

    written = 0
    skipped = 0

    for jsonl_path in all_sessions:
        try:
            s = parse_session(jsonl_path)
        except Exception as e:
            print(f"  ERR {jsonl_path.name}: {e}", file=sys.stderr)
            continue

        if not s:
            skipped += 1
            continue

        slug = s["slug"] or s["short_id"]
        date = s["start"][:10]
        filename = f"{date}-{slug}.md"
        out_path = out_dir / filename

        if args.dry_run:
            print(f"  WOULD WRITE: {filename}")
            print(render_note(s)[:500])
            print("  ...")
            continue

        note = render_note(s)
        out_path.write_text(note, encoding="utf-8")
        print(f"  ✓ {filename}", file=sys.stderr)
        written += 1

    print(f"\nDone: {written} notes written, {skipped} skipped", file=sys.stderr)


if __name__ == "__main__":
    main()
