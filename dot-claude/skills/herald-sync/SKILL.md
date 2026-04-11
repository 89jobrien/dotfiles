---
name: herald-sync
description: Use when synthesizing cross-project activity at end of session, generating a cross-repo narrative summary, or consolidating work from multiple repos into the Obsidian daily note
---

# Herald Sync

Cross-project knowledge capture: collect per-repo standups, synthesize a narrative, write to vault.

## Active Repos

`~/dev/minibox`, `~/dev/devloop`, `~/dev/doob`, `~/dev/devkit`, `~/dev/maestro`, `~/dev/braid`, `~/dev/romp`

## Step 1: Collect per-repo activity

For each repo, check if there's activity before running the expensive council analysis:

```bash
# Quick check — skip repos with no recent commits
git -C ~/dev/<repo> log --oneline --since="24 hours ago" 2>/dev/null | wc -l
```

For repos with activity, run devloop standup:

```bash
export OPENAI_API_KEY=$(sed -n 's/^OPENAI_API_KEY=//p' ~/.secrets)
~/.local/bin/devloop analyze --council --council-mode standard --repo ~/dev/<repo>
git -C ~/dev/<repo> log --format="%ad %s" --date=format:"%H:%M" --since="24 hours ago"
```

Run repos in parallel when multiple are active.

## Step 2: Synthesize cross-project narrative

Write a single narrative spanning all active repos:

```
Cross-project summary, YYYY-MM-DD:

**minibox** — [1-sentence arc]
**devloop** — [1-sentence arc]

Themes: [what connects the work — e.g., "hexagonal refactor wave", "CI stabilization"]
Blockers: [unresolved issues]
Tomorrow: [natural next steps]
```

Rules:
- Only include repos with actual activity (skip idle repos)
- Name cross-cutting themes when the same pattern appears in 2+ repos
- Keep to ~15 lines — dense > verbose

## Step 3: Write to Obsidian daily note

```bash
VAULT=~/Documents/Obsidian\ Vault
TODAY=$(date +%Y-%m-%d)
DAILY="$VAULT/01_Daily/$TODAY.md"
```

> **Note:** vault path has a space — always quote or escape it.

Follow `obsidian-vault` skill conventions (YAML frontmatter, `[[wikilinks]]`). Append under `## Herald Summary` — never overwrite existing content.

## Step 4: Update session memory (optional)

Check `~/.claude/projects/*/memory/` for each active project. Persist:
- Project state changes (new phase, milestone reached, blocker resolved)
- Cross-project architectural decisions made today
- Feedback patterns that recurred across sessions

Use Write tool to update memory files; update `MEMORY.md` index.

## Output

Herald always produces:
1. Cross-project narrative (terminal)
2. Vault write confirmation (path + lines appended)
3. Memory entries created or updated (if any)
