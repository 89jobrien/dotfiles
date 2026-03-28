#!/usr/bin/env python3
"""
[JOEHOOK] PostToolUse hook: enforce uv shebang pattern for Python scripts.

Fires after Write or Edit tool calls on .py files. Warns Claude if the file
uses a bare python3/python shebang instead of the preferred uv PEP 723 pattern.

Preference: Python scripts should use `uv` with PEP 723 inline script metadata,
not `python3` directly. Rejects old-style shebangs.

Always exits 0 (warn-only, never blocks).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import re

OLD_SHEBANGS = (
    "#!/usr/bin/env python3",
    "#!/usr/bin/python3",
    "#!/usr/bin/python",
    "#!/usr/local/bin/python",
)

# Also catch versioned shebangs like #!/usr/bin/python3.11
_OLD_SHEBANG_RE = re.compile(r"^#!.*(python3\.\d+|python\d*)")

HOOKS_DIRS = (
    "/Users/joe/.claude/hooks/",
    "/Users/joe/dotfiles/.claude/hooks/",
)

WARNING_TEMPLATE = """\
[uv-shebang-enforcer] {file_path} uses a python3 shebang. Prefer the uv pattern:

For scripts with dependencies:
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["requests", "rich"]
# ///

For scripts with no dependencies:
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

This enables: uv run script.py (auto-installs deps, no venv needed)
Consider updating the shebang if this script will be run standalone.\
"""


def has_old_shebang(lines: list[str]) -> bool:
    """Check the first 3 lines for a bare python3/python shebang (including versioned variants)."""
    for line in lines[:3]:
        stripped = line.strip()
        for pattern in OLD_SHEBANGS:
            if stripped.startswith(pattern):
                return True
        if _OLD_SHEBANG_RE.match(stripped):
            return True
    return False


def has_pep723_metadata(lines: list[str]) -> bool:
    """Return True if the file already has a PEP 723 inline script metadata block."""
    for line in lines[:20]:
        if line.strip() == "# /// script":
            return True
    return False


def is_hooks_file(file_path: str) -> bool:
    """Return True if the file lives under a hooks directory (exempt from enforcement)."""
    return any(file_path.startswith(d) for d in HOOKS_DIRS)


def main() -> None:
    # Parse stdin — fail open on any error
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    # Only intercept Write and Edit tool calls
    tool_name = data.get("tool_name", "")
    if tool_name not in ("Write", "Edit"):
        sys.exit(0)

    tool_input = data.get("tool_input", {})
    file_path: str = tool_input.get("file_path", "")

    # Only care about .py files
    if not file_path.endswith(".py"):
        sys.exit(0)

    # Skip hook scripts — they intentionally use bare python3 shebangs
    if is_hooks_file(file_path):
        sys.exit(0)

    # Get content to inspect
    if tool_name == "Write":
        # Content available directly in the payload — no disk read needed
        content: str = tool_input.get("content", "")
        lines = content.splitlines()
    else:
        # Edit: read the file from disk (already written by the time PostToolUse fires)
        try:
            lines = Path(file_path).read_text(encoding="utf-8", errors="replace").splitlines()
        except Exception:
            sys.exit(0)

    if has_old_shebang(lines) and not has_pep723_metadata(lines):
        print(WARNING_TEMPLATE.format(file_path=file_path))

    sys.exit(0)


if __name__ == "__main__":
    main()
