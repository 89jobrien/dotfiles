#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""
[JOEHOOK] PostToolUse hook: validate SKILL.md frontmatter after Write or Edit.

Fires after any Write or Edit tool call. If the file written/edited is a
SKILL.md, validates the file has correct frontmatter — specifically that it
contains `name:` and `description:` fields inside a `---` block at the top
of the file.

Because this is a PostToolUse hook it cannot block; it can only warn via
stdout, which Claude Code surfaces as a system message.

Stdin JSON shape:
  {
    "tool_name": "Write" | "Edit",
    "tool_input": {"file_path": "..."},
    "tool_response": {...}
  }

Exit codes:
  0 = always (PostToolUse hooks must always exit 0)
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# I/O helpers — all fail-open
# ---------------------------------------------------------------------------

def allow() -> None:
    """Silent pass-through."""
    sys.exit(0)


def warn(file_path: str) -> None:
    """Print a warning to stdout so Claude Code surfaces it as a system message."""
    print(
        f"[JOEHOOK] [skill-frontmatter-validator] WARNING: {file_path} is missing required frontmatter.\n"
        "\n"
        "A valid SKILL.md must start with:\n"
        "---\n"
        "name: your-skill-name\n"
        "description: Use when ... Symptoms - ...\n"
        "---\n"
        "\n"
        "The skill will not be discoverable without this. Edit the file to add frontmatter."
    )
    sys.exit(0)


# ---------------------------------------------------------------------------
# Frontmatter parsing
# ---------------------------------------------------------------------------

def has_valid_frontmatter(content: str) -> bool:
    """
    Return True if *content* begins with a --- block that contains both
    `name:` and `description:` keys.

    Tolerates trailing whitespace on fence lines and Windows line endings.
    """
    lines = content.splitlines()

    # First line must be the opening fence
    if not lines or lines[0].rstrip() != "---":
        return False

    # Collect lines until the closing fence
    block_lines: list[str] = []
    found_close = False
    for line in lines[1:]:
        if line.rstrip() == "---":
            found_close = True
            break
        block_lines.append(line)

    if not found_close:
        return False

    has_name = any(line.lstrip().startswith("name:") for line in block_lines)
    has_description = any(line.lstrip().startswith("description:") for line in block_lines)

    return has_name and has_description


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    # Parse stdin — fail open on any error
    try:
        data = json.load(sys.stdin)
    except Exception:
        allow()

    tool_name: str = data.get("tool_name", "")

    # Only care about Write and Edit
    if tool_name not in ("Write", "Edit"):
        allow()

    file_path: str = data.get("tool_input", {}).get("file_path", "")
    if not file_path:
        allow()

    # Only validate SKILL.md files
    if not file_path.endswith("SKILL.md"):
        allow()

    # Read the file that was just written — fail open on any I/O or parse error
    try:
        content = Path(file_path).read_text(encoding="utf-8")
    except Exception:
        allow()

    try:
        valid = has_valid_frontmatter(content)
    except Exception:
        allow()

    if valid:
        allow()

    warn(file_path)


if __name__ == "__main__":
    main()
