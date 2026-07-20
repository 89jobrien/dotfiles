---
name: "cmd:handoff:
description: Write session-end HANDOFF.yaml — completed work, new gaps, current state.
allowed-tools: Bash, Read, Write, Edit
argument-hint: '[project]'
author: Joseph O'Brien
---

# Handoff

Run end-of-session handoff for: $ARGUMENTS (infer from cwd if blank).

1. `git branch --show-current && git log --oneline -5`
2. `cargo check 2>&1 | tail -3` (or language equivalent)
3. `hj handoff --log-summary "<one-line summary of this session>"`
4. Verify `.ctx/HANDOFF.*.yaml` was updated and committed
