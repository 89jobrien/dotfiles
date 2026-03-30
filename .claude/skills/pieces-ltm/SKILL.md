---
name: pieces-ltm
description: Use before starting work on a feature or bug to get historical context from 9 months of LTM. Use when you need to know "what did I try before", "why was this decision made", or "what was the state of X last month".
---

## What Pieces LTM Contains

- Claude/AI conversation history (9 months)
- Code snippets saved to Pieces
- Browser activity (research, docs visited)
- Clipboard history
- Git activity context

## Health Check First

```bash
curl -s http://localhost:39300/.well-known/health
# Should return: {"status":"ok"} or similar
# If not: open PiecesOS app on this machine
```

## Query Patterns That Work Well

**Temporal queries** (what was I doing when):
```
"What was I working on in the devloop project in January?"
"What did I research about BAML in the last 3 months?"
```

**Decision archaeology** (why did I do X):
```
"Why did I switch from Docker Desktop to colima?"
"What problems did I hit when setting up the Gitea runner?"
"What was the reason I chose mise over nvm?"
```

**Prior art** (have I solved this before):
```
"Have I written a script to parse op:// env vars before?"
"Did I ever debug a source_up chain issue in direnv?"
"What was the fix for the BAML version mismatch I hit before?"
```

**Current project context** (before starting work):
```
"What's the current state of the minibox CI pipeline?"
"What was I last working on in maestro?"
"What problems were blocking the devloop release?"
```

## When to Use

- **Before devloop analyze**: prime your understanding of recent history
- **Starting a new session on a repo**: get context for what was in-progress
- **Hitting a familiar-feeling bug**: check if you've seen this before
- **Making a tech decision**: check what you've tried or decided previously

## When NOT to Use

- For information in current session context (you already have it)
- For code that's in the repo (use gkg or grep instead)
- For recent git history (use devloop or git log instead)

## Example Workflow

```
1. curl -s http://localhost:39300/.well-known/health  # verify running
2. ask_pieces_ltm: "What was I last working on in [repo]?"
3. ask_pieces_ltm: "What known issues or blockers exist for [feature]?"
4. Proceed with session informed by historical context
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Health check fails | Open PiecesOS app; wait 30s for startup |
| ask_pieces_ltm not found | Check personal-mcp is running in Claude settings |
| Empty/irrelevant results | Rephrase query; try more specific date range or project name |
| Results from wrong context | Add project name to query to narrow scope |
