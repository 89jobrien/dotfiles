#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""
[JOEHOOK] PreToolUse hook: course-correct anti-patterns and learned repeated failures.

Checks Bash tool calls against:
  1. Predefined rules in course-correct-rules.json
  2. Repeated failure patterns learned from post-tool-track-failures.py

Config: ~/.claude/hooks/course-correct-rules.json
State:  ~/.claude/hooks/course-correct-state.json (auto-managed)

Exit codes:
  0 = allow (silent, no output)
  2 = deny  (stderr JSON with hookSpecificOutput + systemMessage)
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


# ---------------------------------------------------------------------------
# I/O helpers — all fail-open
# ---------------------------------------------------------------------------

def load_rules() -> dict:
    try:
        return json.loads(RULES_FILE.read_text())
    except Exception:
        return {"rules": [], "failure_learning": {"enabled": False}}


def load_state(state_path: Path) -> dict:
    try:
        return json.loads(state_path.read_text())
    except Exception:
        return {"failures": {}}


def allow() -> None:
    """Silent allow."""
    sys.exit(0)


def deny(message: str) -> None:
    """Deny the tool use, feeding message back to the agent."""
    payload = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
        },
        "systemMessage": f"[JOEHOOK] {message}",
    }
    print(json.dumps(payload), file=sys.stderr)
    sys.exit(2)


# ---------------------------------------------------------------------------
# Predefined rule checking
# ---------------------------------------------------------------------------

def check_rules(command: str, rules: list[dict]) -> str | None:
    """
    Check command against predefined rules.
    Returns block message on first match, None if all rules pass.
    """
    for rule in rules:
        if not rule.get("enabled", True):
            continue

        # Build regex flags
        flags = 0
        flags_str = rule.get("pattern_flags", "")
        if flags_str:
            if "i" in flags_str or "(?i)" in flags_str:
                flags |= re.IGNORECASE
            if "m" in flags_str or "(?m)" in flags_str:
                flags |= re.MULTILINE

        try:
            pattern = re.compile(rule["pattern"], flags)
        except (re.error, KeyError):
            continue  # Bad rule — skip, fail open

        if not pattern.search(command):
            continue  # Rule doesn't match

        # Rule matched — check exceptions
        for exc_pattern in rule.get("exceptions", []):
            try:
                if re.search(exc_pattern, command):
                    return None  # Exception applies — allow
            except re.error:
                continue

        return rule.get("message", f"Blocked by rule '{rule.get('id', '?')}'.")

    return None


# ---------------------------------------------------------------------------
# Learned failure checking
# ---------------------------------------------------------------------------

def command_key(command: str) -> str:
    return hashlib.sha256(command.encode()).hexdigest()


def check_learned_failures(command: str, fl_config: dict, state: dict) -> str | None:
    """
    Check if this exact command has failed >= threshold times within the window.
    Returns block message if so, None otherwise.
    """
    if not fl_config.get("enabled", True):
        return None

    threshold: int = fl_config.get("block_threshold", 3)
    window: int = fl_config.get("window_seconds", 300)
    now = time.time()

    key = command_key(command)
    entry = state.get("failures", {}).get(key)
    if not entry:
        return None

    recent = [t for t in entry.get("timestamps", []) if now - t <= window]
    if len(recent) < threshold:
        return None

    window_minutes = max(1, window // 60)
    template: str = fl_config.get(
        "message_template",
        "[course-correct] This command has failed {count} times in the last {window} minutes. Try a different approach.\n\nFailing command: {preview}",
    )
    preview = entry.get("command_preview", command[:80])
    return template.format(count=len(recent), window=window_minutes, preview=preview)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    # Parse stdin — fail open on any error
    try:
        data = json.load(sys.stdin)
    except Exception:
        allow()

    # Only intercept Bash tool calls
    if data.get("tool_name") != "Bash":
        allow()

    command: str = data.get("tool_input", {}).get("command", "")
    if not command:
        allow()

    config = load_rules()
    rules: list[dict] = config.get("rules", [])
    fl_config: dict = config.get("failure_learning", {})

    # 1. Predefined rules (no disk I/O beyond rules file already loaded)
    block_msg = check_rules(command, rules)
    if block_msg:
        deny(block_msg)

    # 2. Learned failures (requires reading state file)
    if fl_config.get("enabled", True):
        state_path = Path(fl_config.get("state_file", str(DEFAULT_STATE_FILE))).expanduser()
        state = load_state(state_path)
        block_msg = check_learned_failures(command, fl_config, state)
        if block_msg:
            deny(block_msg)

    allow()


if __name__ == "__main__":
    main()
