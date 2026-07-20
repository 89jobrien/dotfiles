---
name: "cmd:watch"
description: Start sentinel in ongoing monitoring mode — reviews each new diff as you work.
allowed-tools: Bash, Read, Glob, Grep
author: Joseph O'Brien
---

# Watch

Start with the current diff: !`git diff`

Review it for blocking issues, suggestions, and observations. Then monitor each subsequent diff as work continues. Output the standard Blocking / Suggestions / Observations report for each review pass.
