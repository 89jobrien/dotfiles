---
name: doob-context-prime
description: Use at the start of any doob work session to load situational awareness — pending todos, overdue items, kanban state, and recent git activity. Use before starting new features, triaging work, or resuming after a break.
---

# doob: Context Prime

## Overview

Run these three commands to establish full situational awareness before any doob work session.

## Commands

```bash
# 1. Pending + in-progress todos (JSON for parsing)
doob todo list --status pending,in_progress --json

# 2. Visual kanban board
doob kan

# 3. Recent git context
git log --oneline -10
```

## Interpreting Output

**From `todo list --json`:**
- `due_date` past today → overdue, address first
- `status: "in_progress"` with old `updated_at` → stale, may need undo
- High `priority` (>200) + pending → blocking work

**From `kan`:**
- Columns: Pending | In Progress | Completed | Cancelled
- Todos grouped by project — spot cross-project drift

**From `git log`:**
- Match recent commit topics to open todos
- Identify todos that should have been completed by recent commits

## Quick Reference

```bash
# Overdue check (requires jq)
doob todo list --status pending --json | jq '[.todos[] | select(.due_date != null and .due_date < "2026-03-25")]'

# Count by status
doob todo list --json | jq '.todos | group_by(.status) | map({(.[0].status): length}) | add'

# Current project todos only
doob todo list --project $(basename $(git rev-parse --show-toplevel)) --json
```

## When Context Reveals Problems

| Signal | Action |
|---|---|
| Many stale `in_progress` todos | `doob todo undo <id>` to reset them |
| Completed work still marked pending | `doob todo complete <id>` |
| Todos with no project | Add `--project` on next add |
| Nothing pending | Check git log for unreleased work |
