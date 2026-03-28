---
name: doob-bulk-import
description: Use when converting a markdown task list, numbered list, or planning breakdown into doob todos. Symptoms - "add these tasks to doob", "import this plan", "create todos from this list", task breakdowns that need tracking.
---

# doob: Bulk Todo Import

## Overview

Parse a structured task list and batch-create doob todos with inferred priority, tags, and project context.

## Priority Inference Rules

| Signal in text | Priority |
|---|---|
| "critical", "blocker", "must", "p0" | 220 |
| "important", "required", "p1" | 160 |
| "should", "p2" | 100 |
| "nice to have", "p3", "optional" | 40 |
| No signal (default) | 0 |

## Import Pattern

Given a task list like:
```
- [ ] Implement SurrealDB sync metadata repository (critical)
- [ ] Add `doob sync to` CLI command
- [ ] Write integration tests for GitHub adapter
- [ ] Update README provider table (optional)
```

Run:
```bash
doob todo add "Implement SurrealDB sync metadata repository" --priority 220 --tags phase-3
doob todo add "Add doob sync to CLI command" --tags phase-4
doob todo add "Write integration tests for GitHub adapter" --tags testing
doob todo add "Update README provider table" --priority 40 --tags docs
```

## Auto-Tag Rules

- Items mentioning a phase/milestone → tag with `phase-N`
- Items about tests → tag with `testing`
- Items about docs/README → tag with `docs`
- Items about a specific provider → tag with provider name
- Current git branch matches `feature/*` → tag with branch slug

## Batch Script (for large imports)

```bash
# Run from doob project root
while IFS= read -r line; do
  # Strip markdown list markers
  task=$(echo "$line" | sed 's/^[[:space:]]*[-*] \(\[ \] \)\?//')
  [[ -z "$task" ]] && continue
  doob todo add "$task" --project doob
done << 'EOF'
- [ ] task one
- [ ] task two
EOF
```

## Verification

```bash
doob todo list --project doob --json | jq '.count'
```
