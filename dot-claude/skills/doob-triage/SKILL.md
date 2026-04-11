---
name: doob-triage
description: Prioritized todo triage for the current project — runs doob todo list filtered to current repo, sorts by priority score, picks the highest-priority item to start, marks it in-progress, and creates a task checklist. Use at the start of a session or when asking "what should I work on next?"
---

# Doob Triage

Fast workflow for picking the highest-priority doob todo and starting work on it.

## Step 1 — List todos for current project

```bash
# Get the current project path (doob uses the repo path as project key)
PROJECT=$(git rev-parse --show-toplevel 2>/dev/null | xargs basename)
doob todo list --project "$PROJECT" 2>/dev/null
```

If `--project` filtering isn't supported, fall back to:
```bash
doob todo list 2>/dev/null | head -40
```

## Step 2 — Parse and sort by priority

Doob todos often have priority scores in the description: `P100`, `P75`, `P50`, `P25`.

Sort descending: P100 > P75 > P50 > P25 > (no score).

If multiple todos share the same priority, prefer:
1. Oldest created date (longest-standing)
2. Alphabetically by description

Present a compact table:

```
Pending todos (devloop)
========================
[P100] Add PII level-gating to obfsck — --pii off flag + tests            (obfsck)
[P75]  Fix username redaction regex \w+ → [A-Za-z0-9._-]+                 (obfsck)
[P50]  Integration tests for redact CLI file I/O                           (obfsck)
[P50]  Narrow GitHub secret-scanning ignore rules                          (obfsck)
[P25]  Combine UUID + hex scans into one pass                              (obfsck)
[P25]  Streaming I/O + cached regex                                        (obfsck)
[P25]  Golden/snapshot tests for demo fixtures                             (obfsck)
[P25]  Document new CLI flags in README                                    (obfsck)
```

## Step 3 — Recommend the top item

Pick the highest-priority, oldest item and explain it briefly:

```
Recommendation: Start with [P100] obfsck PII level-gating
Reason: Highest priority, establishes invariants needed for other obfsck work.
```

Ask: "Start with this one?" (or proceed if context makes it obvious)

## Step 4 — Mark in-progress

When the user confirms:

```bash
doob todo start <uuid> 2>/dev/null || echo "No UUID available — update manually"
```

## Step 5 — Create task checklist

Break the selected todo into a task checklist using TaskCreate. Example for PII gating:

```
1. Read current level-gating code in src/lib.rs and config/secrets.yaml
2. Write failing tests asserting minimal leaves PII untouched
3. Implement --pii off flag in src/bin/redact.rs (if needed)
4. Verify all three levels: minimal (PII untouched), standard (PII redacted), paranoid (PII redacted)
5. Update README if new flag added
6. Run full test suite
7. Commit with "closes <uuid>"
```

Adjust the checklist based on the actual todo description.

## Quick reference

```bash
# List all
doob todo list

# Start a specific todo
doob todo start <uuid>

# Complete when done
doob todo complete <uuid>

# Add a new todo
doob todo add "description" --project devloop --priority 75
```

## Priority score guide

| Score | Meaning |
|-------|---------|
| P100  | Critical — blocks other work or is a security/correctness issue |
| P75   | High — meaningful improvement, should be done soon |
| P50   | Medium — good to have, fits in sprint |
| P25   | Low — nice to have, do when other work is done |
| (none)| Unscored — treat as P25 |
