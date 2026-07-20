---
name: "cmd:inspect"
description: Run a targeted one-shot code review on the current diff or specified files.
allowed-tools: Bash, Read, Glob, Grep
argument-hint: '[file or path] [-- <git ref>]'
author: Joseph O'Brien
---

# Inspect

Target: $ARGUMENTS (use current `git diff` if no arguments given).

Review the target and output the full Blocking / Suggestions / Observations report. One pass only.
