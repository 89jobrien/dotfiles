---
name: "cmd:navigate"
description: Prime your mental model for a repo — get a concise architecture briefing.
allowed-tools: Bash, Read, Glob, Grep
argument-hint: '[repo name or leave blank to infer from cwd]'
author: Joseph O'Brien
---

# Navigate

Prime context for: $ARGUMENTS (infer from cwd if no argument given).

1. Run `git log --oneline -5` and `git status --short`
2. Read CLAUDE.md, README.md, and any docs/ or ai_docs/ at the repo root
3. List top-level structure
4. Produce a concise architecture briefing: purpose, crate/module layout, key entry points, active branch state
5. Stay available for follow-up architecture questions
