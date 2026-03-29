#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""
[JOEHOOK] PostToolUse/Bash hook: track command failures for learned course correction.

Records Bash commands that exit non-zero into the state file consumed by
pre-tool-course-correct.py. When a command fails enough times in the window,
the pre-hook will block it and prompt the agent to try a different approach.

Config: ~/.claude/hooks/course-correct-rules.json
State:  ~/.claude/hooks/course-correct-state.json (auto-managed)
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
import time
from pathlib import Path

HOOKS_DIR = Path(__file__).parent
RULES_FILE = HOOKS_DIR / "course-correct-rules.json"
DEFAULT_STATE_FILE = HOOKS_DIR / "course-correct-state.json"

# Exit codes that mean "user or OS interrupted" — not a logic failure worth tracking
_SIGNAL_EXIT_CODES = {130, 137, 143}

# Commands that fail by design — tracking them creates noise
_EXCLUDE_PATTERNS = [
    re.compile(r"^\s*false\s*$"),           # `false` always exits 1
    re.compile(r"\|\|\s*(true|:)\s*$"),     # foo || true idiom
    re.compile(r";\s*(true|:)\s*$"),        # foo; true idiom
    re.compile(r"^\s*\["),                  # [ condition ] expressions
    re.compile(r"\btest\s+-[defhlrswxz]\b"),  # test -f / test -d / etc.
    re.compile(r"2>/dev/null"),             # Caller knows it may fail silently
    re.compile(r">/dev/null\s+2>&1"),
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def load_rules() -> dict:
    try:
        return json.loads(RULES_FILE.read_text())
    except Exception:
        return {"failure_learning": {"enabled": False}}


def load_state(state_path: Path) -> dict:
    try:
        return json.loads(state_path.read_text())
    except Exception:
        return {"failures": {}}


def save_state(state_path: Path, state: dict) -> None:
    """Atomic write via temp file + rename to avoid partial writes."""
    tmp = state_path.with_suffix(".tmp")
    try:
        state_path.parent.mkdir(parents=True, exist_ok=True)
        tmp.write_text(json.dumps(state, indent=2))
        tmp.replace(state_path)
    except Exception:
        try:
            tmp.unlink(missing_ok=True)
        except Exception:
            pass


def command_key(command: str) -> str:
    return hashlib.sha256(command.encode()).hexdigest()


def should_track(command: str, exit_code: int) -> bool:
    if exit_code in _SIGNAL_EXIT_CODES:
        return False
    for pattern in _EXCLUDE_PATTERNS:
        if pattern.search(command):
            return False
    return True


def prune_state(
    state: dict,
    window: int,
    max_entries: int,
    cleanup_after: int,
) -> dict:
    """
    - Remove timestamps older than window
    - Remove entries with no recent timestamps
    - Remove entries with last_seen older than cleanup_after
    - Evict oldest entries if over max_entries
    """
    now = time.time()
    failures: dict = state.get("failures", {})

    stale = [
        k for k, v in failures.items()
        if now - v.get("last_seen", 0) > cleanup_after
    ]
    for k in stale:
        del failures[k]

    empty = []
    for k, v in failures.items():
        v["timestamps"] = [t for t in v.get("timestamps", []) if now - t <= window]
        if not v["timestamps"]:
            empty.append(k)
    for k in empty:
        del failures[k]

    if len(failures) > max_entries:
        by_age = sorted(failures, key=lambda k: failures[k].get("last_seen", 0))
        for k in by_age[: len(failures) - max_entries]:
            del failures[k]

    state["failures"] = failures
    return state


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    if data.get("tool_name") != "Bash":
        sys.exit(0)

    tool_response = data.get("tool_response", {})
    exit_code: int = tool_response.get("exit_code", 0)

    if exit_code == 0:
        sys.exit(0)

    command: str = data.get("tool_input", {}).get("command", "")
    if not command or not should_track(command, exit_code):
        sys.exit(0)

    config = load_rules()
    fl_config: dict = config.get("failure_learning", {})
    if not fl_config.get("enabled", True):
        sys.exit(0)

    window: int = fl_config.get("window_seconds", 300)
    max_entries: int = fl_config.get("max_tracked_commands", 200)
    cleanup_after: int = fl_config.get("cleanup_after_seconds", 3600)
    state_path = Path(
        fl_config.get("state_file", str(DEFAULT_STATE_FILE))
    ).expanduser()

    state = load_state(state_path)
    now = time.time()
    key = command_key(command)

    failures: dict = state.setdefault("failures", {})
    entry = failures.setdefault(key, {
        "command_preview": command[:80],
        "timestamps": [],
        "last_seen": 0.0,
    })
    entry["timestamps"].append(now)
    entry["last_seen"] = now
    entry["command_preview"] = command[:80]  # refresh on each failure

    state = prune_state(state, window, max_entries, cleanup_after)
    save_state(state_path, state)

    sys.exit(0)


if __name__ == "__main__":
    main()
