#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""
[JOEHOOK] PreToolUse hook: destructive-service-guardian.

Intercepts Bash commands that match known destructive patterns for shared
services and blocks them, requiring explicit user confirmation before proceeding.

Background: Operations such as resetting a Gitea admin password can silently set
`must_change_password=true`, invalidating API tokens and breaking CI/devloop
integrations. This hook acts as a safety gate for such operations.

Exit codes:
  0 = allow (silent, no output)
  2 = deny  (stderr JSON with hookSpecificOutput + systemMessage)
"""

from __future__ import annotations

import json
import re
import sys

DESTRUCTIVE_PATTERNS = [
    {
        "id": "gitea-password-reset",
        "pattern": r"gitea\s+admin\s+user\s+(change-password|reset-password|create)",
        "description": "Gitea admin user credential operation",
        "impact": "May set must_change_password=true and break API tokens",
    },
    {
        "id": "op-item-edit",
        "pattern": r"op\s+item\s+(edit|delete|create|update)",
        "description": "1Password item modification",
        "impact": "Permanently modifies or deletes credential store entries",
    },
    {
        "id": "docker-passwd",
        "pattern": r"docker\s+exec.+passwd\s+|docker\s+exec.+chpasswd",
        "description": "Container password change",
        "impact": "Changes credentials inside a running container",
    },
    {
        "id": "psql-alter-user",
        "pattern": r"ALTER\s+USER|ALTER\s+ROLE",
        "pattern_flags": "IGNORECASE",
        "description": "PostgreSQL user/role modification",
        "impact": "Changes database credentials or permissions",
    },
    {
        "id": "systemctl-shared",
        "pattern": r"systemctl\s+(restart|stop|disable|mask)\s+(gitea|postgres|mysql|nginx|caddy|traefik)",
        "description": "Shared service restart/stop",
        "impact": "Interrupts a shared infrastructure service",
    },
    {
        "id": "git-push-force",
        "pattern": r"git\s+push.+--force(?!-with-lease)|git\s+push.+-f\b",
        "description": "Force push (destructive git history rewrite)",
        "impact": "Overwrites remote history, may destroy teammates' work",
    },
    {
        "id": "drop-database",
        "pattern": r"DROP\s+(DATABASE|TABLE|SCHEMA)\s+(?!IF\s+EXISTS\s+test|IF\s+EXISTS\s+dev)",
        "pattern_flags": "IGNORECASE",
        "description": "Database/table drop",
        "impact": "Permanently destroys data",
    },
]


# ---------------------------------------------------------------------------
# I/O helpers
# ---------------------------------------------------------------------------


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
# Pattern matching
# ---------------------------------------------------------------------------


def check_destructive_patterns(command: str) -> tuple[dict, None] | tuple[None, None]:
    """
    Check command against DESTRUCTIVE_PATTERNS in order.
    Returns the first matching pattern dict, or None if no match.
    """
    for entry in DESTRUCTIVE_PATTERNS:
        flags = 0
        flags_str = entry.get("pattern_flags", "")
        if "IGNORECASE" in flags_str:
            flags |= re.IGNORECASE

        try:
            pattern = re.compile(entry["pattern"], flags)
        except re.error:
            continue  # Bad pattern — skip, fail open

        if pattern.search(command):
            return entry, None

    return None, None


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

    try:
        matched, _ = check_destructive_patterns(command)
    except Exception:
        allow()  # Fail open on any unexpected error

    if matched is None:
        allow()

    command_preview = command[:120] + ("…" if len(command) > 120 else "")

    message = (
        f"[destructive-guardian] STOP — destructive operation detected.\n\n"
        f"Pattern: {matched['description']}\n"
        f"Risk: {matched['impact']}\n"
        f"Command: {command_preview}\n\n"
        f"This action may be irreversible. Do NOT proceed until the user explicitly "
        f'confirms with something like "yes, go ahead" or "confirmed". Ask the user first.'
    )

    deny(message)


if __name__ == "__main__":
    main()
