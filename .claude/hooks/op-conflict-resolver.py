#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""
[JOEHOOK] PreToolUse hook: detect environment variable conflicts with `op run`.

When `op run` is used to inject 1Password secrets into a command's environment,
any variable that is ALREADY set in the current shell environment will shadow the
op:// reference — 1Password silently loses the race and the stale value is used.

This hook intercepts Bash commands containing `op run` and checks two sources for
conflicts:

  1. Direct env pollution: variables currently in os.environ whose VALUE starts
     with `op://` (i.e. direnv or a dotfile exported an unresolved op:// URI).
  2. --env-file conflicts: if the command passes `--env-file <path>` to op run,
     the file is read and any var defined there (with an op:// value) that is
     ALSO already present in os.environ is flagged.

When conflicts are found the hook blocks the command and returns the exact
corrected command with `env -u VAR ...` prefixes so that op run can inject the
real secret values unobstructed.

Exit codes:
  0 = allow (silent, no output)
  2 = deny  (stderr JSON with hookSpecificOutput + systemMessage)
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# I/O helpers — all fail-open
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
# Conflict detection helpers
# ---------------------------------------------------------------------------

def find_direct_env_conflicts() -> list[str]:
    """
    Return names of env vars whose current value starts with 'op://',
    indicating an unresolved 1Password reference living in the shell env.
    """
    conflicts: list[str] = []
    for name, value in os.environ.items():
        if value.startswith("op://"):
            conflicts.append(name)
    return conflicts


def find_env_file_conflicts(command: str) -> list[str]:
    """
    If the command contains --env-file <path>, read that file and return the
    names of any vars defined with an op:// value that are ALSO set in the
    current os.environ (meaning op run would be shadowed).
    """
    conflicts: list[str] = []

    # Match --env-file followed by a path (handles optional = separator and
    # single/double-quoted paths as well as bare paths).
    match = re.search(r'--env-file[=\s]+(["\']?)(\S+)\1', command)
    if not match:
        return conflicts

    env_file_path = Path(match.group(2)).expanduser()
    try:
        text = env_file_path.read_text()
    except Exception:
        return conflicts  # Can't read file — fail open

    for line in text.splitlines():
        line = line.strip()
        # Skip comments and blank lines
        if not line or line.startswith("#"):
            continue
        # Accept KEY=value or KEY = value
        if "=" not in line:
            continue
        var_name, _, var_value = line.partition("=")
        var_name = var_name.strip()
        var_value = var_value.strip().strip("'\"")
        if var_value.startswith("op://") and var_name in os.environ:
            conflicts.append(var_name)

    return conflicts


def find_already_unset_vars(command: str) -> set[str]:
    """
    Parse any `env -u VAR` prefixes already present in the command string
    and return the set of variable names that are already being unset.
    This prevents the hook from looping when a corrected command is re-run.
    """
    already_unset: set[str] = set()
    # Match: env (-u VAR)+ at the start of the command (possibly nested)
    for match in re.finditer(r'\benv\s+((?:-u\s+\S+\s*)+)', command):
        for var_match in re.finditer(r'-u\s+(\S+)', match.group(1)):
            already_unset.add(var_match.group(1))
    return already_unset


def build_corrected_command(original: str, conflict_vars: list[str]) -> str:
    """Prepend `env -u VAR1 -u VAR2 ...` to the original command."""
    unset_flags = " ".join(f"-u {v}" for v in sorted(conflict_vars))
    return f"env {unset_flags} {original}"


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

    # Only relevant when op run is involved
    if "op run" not in command:
        allow()

    try:
        # Vars already being unset by existing env -u prefixes in the command
        already_unset = find_already_unset_vars(command)

        conflicts: list[str] = []

        # Source 1: vars in the current environment with unresolved op:// values
        conflicts.extend(find_direct_env_conflicts())

        # Source 2: vars referenced in an --env-file that are already in env
        conflicts.extend(find_env_file_conflicts(command))

        # Remove vars that are already being unset by the command itself
        conflicts = [v for v in conflicts if v not in already_unset]

        # Deduplicate while preserving first-seen order
        seen: set[str] = set()
        unique_conflicts: list[str] = []
        for v in conflicts:
            if v not in seen:
                seen.add(v)
                unique_conflicts.append(v)

        if not unique_conflicts:
            allow()

        corrected = build_corrected_command(command, unique_conflicts)
        var_list = ", ".join(sorted(unique_conflicts))
        n = len(unique_conflicts)

        message = (
            f"[op-conflict-resolver] Found {n} environment var{'s' if n != 1 else ''} "
            f"that conflict with op:// resolution: {var_list}\n\n"
            "These vars are already set in shell and will block op run from injecting "
            "the 1Password values.\n\n"
            f"Corrected command:\n{corrected}\n\n"
            "Re-run with the corrected command above."
        )
        deny(message)

    except Exception:
        # Fail open — never block the user due to a hook bug
        allow()


if __name__ == "__main__":
    main()
