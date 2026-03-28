---
name: obsidian-vault
description: Use when working in the Obsidian Vault directory — creating notes, editing vault content, running vault scripts, or answering questions about projects/experiments/infrastructure tracked in the vault
---

# Obsidian Vault

## Overview

Personal knowledge base in Obsidian with strict note conventions. Every note needs YAML frontmatter, uses templates, and maintains `[[wikilink]]` backlinks.

## When to Use

- Creating or editing any `.md` file in the vault
- Running vault maintenance scripts (`just` commands)
- Looking up project/experiment/infrastructure context
- NOT for: editing code in external repos (even if documented here)

## Folder Map

| Folder | What goes here |
|---|---|
| `00_Inbox` | Unsorted captures |
| `01_Daily` | Daily journal notes |
| `02_Projects` | One subfolder per project — files named `PROJECT.<name>.md`, `STRUCTURE.<name>.md`, etc. |
| `03_Area-Systems` | Ongoing non-project areas |
| `04_Research` | Papers, analysis, extraction notes |
| `05_Knowledge` | Concepts, backlink maps, relationship reports |
| `06_Experiments` | Experiment logs |
| `07_Infrastructure` | Machine configs, toolchain, `Programs/` catalog |
| `08_Templates` | Templater templates (use these for new notes) |
| `09_Archive` | Inactive content |

## Quick Reference: Frontmatter by Note Type

| Type | Required fields |
|---|---|
| **project** | `type: project`, `status`, `language_stack`, `domain`, `repo` (url+path), `primary_machine`, `related_experiments`, `tags` |
| **experiment** | `type: experiment`, `id: EXP-{date}-##`, `project`, `status`, `machine`, `code_branch`, `dataset`, `model`, `metrics`, `tags` |
| **daily** | `type: daily`, `date`, `focus` (project+theme), `tags` |
| **research** | `type: research`, `source_type`, `citation`, `topic`, `status`, `tags` |
| **concept** | `type: concept`, `domain`, `level`, `related_concepts`, `tags` |

## Rules

1. **Always use templates** from `08_Templates/` when creating new notes
2. **Always include YAML frontmatter** — update `type`, `status`, `project`, `machine`, `tags`
3. **Use `[[Note Name]]` wikilinks** when referencing other notes
4. **Maintain backlinks**: projects<->experiments, experiments<->research, knowledge<->projects
5. **Specify target machine** when suggesting scripts/configs: `$INFRA_DEV_HOST` (dev workstation) or `$INFRA_LAB_HOST` (M3 homelab/devserver — not yet on Tailscale network, being set up)
6. **Use Tailscale 100.x addresses** for internal service endpoints
7. **Read existing notes first** — prefer vault context over assumptions about environment/conventions

## Commands

```bash
just                          # List tasks
just build-project-graph      # Build backlink graph -> 05_Knowledge/
just check-project-graph      # Dry-run check
just project-graph            # Check + build
just project-graph-candidates # Relationship candidate report
just project-structure-notes  # Generate structure notes
```

Scripts in `scripts/python/`, run with `python3`.

## Common Mistakes

- Creating notes without frontmatter or with incomplete fields
- Using bare text references instead of `[[wikilinks]]`
- Forgetting to specify which machine a script/config targets
- Putting project notes in wrong folder (use `02_Projects/<name>/`)
- Not using the template when one exists for that note type
