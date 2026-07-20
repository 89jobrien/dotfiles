---
name: "cmd:handon"
description: Orient to outstanding work at session start — triage HANDOFF items by priority.
allowed-tools: Bash, Read
author: Joseph O'Brien
---

# Handon

Run: !`hj handon`

Read the output and triage:
- P0: validate current state, report to user, ask before acting
- P1: execute autonomously, stop if scope expands
- P2: delegate to subagents (cap 5 concurrent)
