---
name: inspect
description: Run a targeted one-shot code review via sentinel on the current diff or specified files.
allowed-tools: Agent
argument-hint: '[file or path] [-- <git ref>]'
author: Joseph OBrien
tag: commands
---

# Inspect

Use the @sentinel agent in inspect mode. Review $ARGUMENTS (or the current `git diff` if no arguments given). Output the full Blocking / Suggestions / Observations report.
