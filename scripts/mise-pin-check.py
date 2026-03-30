#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Compare tool version pins between .mise.toml (repo-local) and
mise/.config/mise/config.toml (global stow package).

Reports: missing from global, missing from local, version mismatches.
Exits non-zero if any mismatches found.
"""

import re
import sys
from pathlib import Path


def parse_tools_section(text: str) -> dict[str, str]:
    """Extract [tools] section key=value pairs (ignoring npm:/cargo:/pipx: prefixes for matching)."""
    in_tools = False
    tools: dict[str, str] = {}
    for line in text.splitlines():
        stripped = line.strip()
        if stripped == "[tools]":
            in_tools = True
            continue
        if in_tools and stripped.startswith("["):
            in_tools = False
            continue
        if not in_tools or not stripped or stripped.startswith("#"):
            continue
        # match: key = "value" or key = value
        m = re.match(r'^"?([^"=\s]+)"?\s*=\s*"?([^"#\s]+)"?', stripped)
        if m:
            tools[m.group(1)] = m.group(2)
    return tools


def bare_name(key: str) -> str:
    """Strip npm:/cargo:/pipx: prefix for cross-file comparison."""
    for prefix in ("npm:", "cargo:", "pipx:", "go:"):
        if key.startswith(prefix):
            return key[len(prefix):]
    return key


def main() -> int:
    root = Path(__file__).parent.parent
    local_path = root / ".mise.toml"
    global_path = root / "mise" / ".config" / "mise" / "config.toml"

    if not local_path.exists():
        print(f"ERR: not found: {local_path}", file=sys.stderr)
        return 1
    if not global_path.exists():
        print(f"ERR: not found: {global_path}", file=sys.stderr)
        return 1

    local_tools = parse_tools_section(local_path.read_text())
    global_tools = parse_tools_section(global_path.read_text())

    # Build bare-name maps for cross-comparison
    local_bare = {bare_name(k): (k, v) for k, v in local_tools.items()}
    global_bare = {bare_name(k): (k, v) for k, v in global_tools.items()}

    mismatches = []
    only_local = []
    only_global = []

    for name, (lk, lv) in local_bare.items():
        if name in global_bare:
            gk, gv = global_bare[name]
            # Skip "latest" — intentionally unpinned
            if lv == "latest" or gv == "latest":
                continue
            # Loose pin: local "1.91" matches global "1.91.1" (prefix match)
            if gv.startswith(lv + ".") or lv.startswith(gv + ".") or lv == gv:
                continue
            # Major-only pin: local "22" matches global "22.22.1"
            if gv.startswith(lv + ".") or gv == lv:
                continue
            mismatches.append((name, lk, lv, gk, gv))
        else:
            only_local.append((name, lk, lv))

    for name, (gk, gv) in global_bare.items():
        if name not in local_bare:
            only_global.append((name, gk, gv))

    ok = True

    if mismatches:
        ok = False
        print("VERSION MISMATCHES (local vs global):")
        for name, lk, lv, gk, gv in sorted(mismatches):
            print(f"  {name}: local={lv!r}  global={gv!r}")
        print()

    if only_local:
        print("ONLY IN .mise.toml (not in global config):")
        for name, key, ver in sorted(only_local):
            print(f"  {key} = {ver!r}")
        print()

    if only_global:
        print("ONLY IN global config (not in .mise.toml):")
        for name, key, ver in sorted(only_global):
            print(f"  {key} = {ver!r}")
        print()

    if ok and not only_local and not only_global:
        print("ok: all shared pins match")
    elif ok:
        print("ok: no version mismatches (some tools are local-only or global-only)")

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
