---
name: rtk
description: Show RTK token savings, Claude Code economics, and hook audit metrics.
allowed-tools: Bash
argument-hint: '[gain|econ|audit|discover]'
author: Joseph OBrien
tag: commands
---

# RTK Stats

Run the following based on $ARGUMENTS (default: all three):

- `gain` → `rtk gain --graph`
- `econ` → `rtk cc-economics`
- `audit` → `rtk hook-audit`
- `discover` → `rtk discover`
- (no args or `all`) → run gain + econ + audit in sequence

Present results inline. No preamble.
