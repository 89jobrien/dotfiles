#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""PostToolUse hook: sync Claude session memory files to Obsidian vault KG.

Triggered on Write|Edit. Exits 0 immediately for non-memory writes.
For memory writes, regenerates the CONTEXT.<project>.md note in the vault.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

VAULT_ROOT = Path("/Users/joe/Documents/Obsidian Vault")
PROJECTS_ROOT = Path.home() / ".claude/projects"

# slug -> (vault_note_path_relative, project_name, related_wikilinks)
PROJECT_MAP: dict[str, tuple[str, str, list[str]]] = {
    "-Users-joe-dev-devloop": (
        "02_Projects/devloop/CONTEXT.devloop.md",
        "devloop",
        ["PROJECT.devloop", "STRUCTURE.devloop"],
    ),
    "-Users-joe-dev-minibox": (
        "02_Projects/minibox/CONTEXT.minibox.md",
        "minibox",
        ["PROJECT.minibox", "STRUCTURE.minibox"],
    ),
    "-Users-joe-Documents-Obsidian-Vault": (
        "03_Area-Systems/CONTEXT.obsidian-vault.md",
        "obsidian-vault",
        ["GitHub Repos - Assessment", "Project Backlink Map"],
    ),
    "-Users-joe-dev-pieces-ob": (
        "02_Projects/pieces-ob/CONTEXT.pieces-ob.md",
        "pieces-ob",
        ["Project Backlink Map"],
    ),
    "-Users-joe--claude": (
        "03_Area-Systems/CONTEXT.claude-config.md",
        "claude-config",
        [],
    ),
}

KNOWN_PREFIXES = ("feedback_", "project_", "reference_", "user_", "infra_")

# ---------------------------------------------------------------------------
# Pure functions (testable without side effects)
# ---------------------------------------------------------------------------

def is_memory_file(file_path: str) -> bool:
    """Return True if file_path is inside a ~/.claude/projects/<slug>/memory/ dir."""
    p = Path(file_path)
    parts = p.parts
    try:
        mem_idx = parts.index("memory")
    except ValueError:
        return False
    if mem_idx < 2:
        return False
    projects_idx = mem_idx - 2
    return parts[projects_idx] == "projects" and p.suffix == ".md"


def extract_slug(file_path: str) -> str:
    """Extract project slug from a memory file path."""
    p = Path(file_path)
    return p.parent.parent.name


def derive_topic(filename: str) -> str:
    """Derive a topic string from a memory filename.

    Strip .md, strip the first matching known prefix (single pass),
    replace underscores with hyphens.
    """
    stem = Path(filename).stem
    for prefix in KNOWN_PREFIXES:
        if stem.startswith(prefix):
            stem = stem[len(prefix):]
            break
    return stem.replace("_", "-")


def read_memory_files(memory_dir: Path) -> list[tuple[str, str]] | None:
    """Read all memory files, skipping MEMORY.md.

    Returns list of (stem, content) sorted by filename, or None if empty.
    """
    files = sorted(
        f for f in memory_dir.glob("*.md") if f.name != "MEMORY.md"
    )
    if not files:
        return None
    return [(f.stem, f.read_text(encoding="utf-8")) for f in files]


def render_context_note(
    slug: str,
    project_name: str,
    files: list[tuple[str, str]],
    wikilinks: list[str],
) -> str:
    """Render the full CONTEXT note content."""
    topics = [derive_topic(f"{stem}.md") for stem, _ in files]
    topic_yaml = "[" + ", ".join(topics) + "]"
    tags_yaml = f"[claude-memory, {project_name}, session-context]"

    lines: list[str] = [
        "---",
        "type: research",
        "source_type: claude-session-memory",
        f'citation: "~/.claude/projects/{slug}/memory"',
        f"topic: {topic_yaml}",
        "status: active",
        f"tags: {tags_yaml}",
        "---",
        "",
        f"# Claude Session Context — {project_name}",
        "",
        "> Auto-generated from Claude Code session memory. Do not edit manually.",
        f"> Source: `~/.claude/projects/{slug}/memory/`",
    ]

    for stem, content in files:
        lines += ["", "---", "", f"## {stem}", "", content.rstrip()]

    if wikilinks:
        lines += ["", "---", "", "## Links", ""]
        for wl in wikilinks:
            lines.append(f"[[{wl}]]")

    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    try:
        data = json.load(sys.stdin)
        file_path = data.get("tool_input", {}).get("file_path", "")
    except Exception:
        return 0  # malformed stdin — not our concern

    if not is_memory_file(file_path):
        return 0

    slug = extract_slug(file_path)

    if slug not in PROJECT_MAP:
        print(
            f"sync_memory_to_vault: unknown project slug '{slug}' — add to PROJECT_MAP to enable sync",
            file=sys.stderr,
        )
        return 0

    vault_rel, project_name, wikilinks = PROJECT_MAP[slug]
    memory_dir = PROJECTS_ROOT / slug / "memory"

    files = read_memory_files(memory_dir)
    if files is None:
        return 0

    note_content = render_context_note(slug, project_name, files, wikilinks)

    vault_path = VAULT_ROOT / vault_rel
    vault_path.parent.mkdir(parents=True, exist_ok=True)
    vault_path.write_text(note_content, encoding="utf-8")

    return 0


if __name__ == "__main__":
    sys.exit(main())
