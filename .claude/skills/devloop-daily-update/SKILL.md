---
name: devloop-daily-update
description: Use when asked to update today's daily note, write a standup, or summarize what happened in a repo and record it in the Obsidian vault. Combines devloop council analysis with Obsidian daily note creation.
---

# Devloop → Daily Note Update

## Overview

Three-step workflow: run council analysis on the repo, synthesize a narrative timeline, write it into today's Obsidian daily note. Each step depends on the previous — don't skip synthesis.

## Steps

### 1. Get git commits for the window

```bash
git log --format="%ad %s" --date=format:"%H:%M" --since="24 hours ago"
```

Group by time block: Morning (06–12), Afternoon (12–17), Evening (17–21), Late evening (21–24), Early morning (00–06).

### 2. Run devloop council analysis

```bash
export OPENAI_API_KEY=$(grep ^OPENAI_API_KEY ~/.secrets | cut -d= -f2)
~/.local/bin/devloop analyze --council --council-mode extensive --repo /path/to/repo
```

Run in background — takes 60–120s. Capture synthesis section (meta health score, consensus, divergent perspectives, action items).

### 3. Find or create today's daily note

Check `01_Daily/YYYY-MM-DD.md`. If it doesn't exist, create from template:

```
/Users/joe/Documents/Obsidian Vault/08_Templates/Template - Daily.md
```

Frontmatter:
```yaml
---
type: daily
date: 2026-03-19
tags: [daily, log]
focus:
  - project: <main project>
  - theme: <main theme>
---
```

### 4. Write the narrative log

Format:

```
Single branch (main), N commits, N sessions.

All work on YYYY-MM-DD:

- **Morning (HH:MM–HH:MM):** [what happened — name themes, not just commits]
- **Afternoon (HH:MM–HH:MM):** [...]
- **Evening (HH:MM–HH:MM):** [name sagas if there were any]

[Council findings if notable — health score, key risk, action items]

Session ended with: [outcome / current state]
```

**Rules:**
- Skip empty time blocks
- Name recurring themes (e.g. "the self-hosted runner saga") not just list commits
- Fold council findings at the bottom, not inline
- Keep to ~10 lines — dense over verbose

### 5. Add links section

```markdown
# Links
- [[PROJECT.name]]
- [[relevant diagram or note]]
```

## Daily Note Location

```
/Users/joe/Documents/Obsidian Vault/01_Daily/YYYY-MM-DD.md
```

## OPENAI_API_KEY Note

`source ~/.secrets` doesn't export vars — use the explicit grep form above. The key is on a line like `OPENAI_API_KEY=sk-...`.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Writing directly from git log without synthesis | Produces a commit list, not a narrative — synthesize first |
| Using wrong date (yesterday's note) | Today is always `date +%Y-%m-%d` |
| Skipping council if it times out | Use git log alone but note council wasn't run |
| Embedding council JSON verbatim | Extract only: health score, 1-2 key findings, P0 action items |
| No `focus` frontmatter | Fill in project + theme — used by vault graph scripts |
