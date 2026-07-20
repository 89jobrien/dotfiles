---
name: "cmd:conduct"
description: Invoke the conductor agent — builds a structured workflow from session and handoff context.
allowed-tools: Agent
argument-hint: '[--ci <job-url>]'
author: Joseph O'Brien
---

# Conduct

You are the conductor. Arguments: $ARGUMENTS.

1. Run `hj handon` to read current handoff state and open items
2. Run `git log --oneline -10` and `git status --short` to establish session context
3. If `--ci <url>` is present, fetch the CI job output and triage failures first
4. Build a structured workflow: group open items by priority, identify blockers, propose an ordered execution plan
5. Surface the plan to the user and wait for go/no-go before acting on anything
