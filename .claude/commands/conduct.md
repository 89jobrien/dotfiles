---
name: conduct
description: Run the devloop → doob → devkit workflow pipeline on the current branch via conductor.
allowed-tools: Agent
argument-hint: '[--ci <job-url>]'
author: Joseph OBrien
tag: commands
---

# Conduct

Use the @conductor agent to run the workflow pipeline. Arguments: $ARGUMENTS. If --ci flag is present, run in CI failure mode. Otherwise run the standard devloop → doob loop.
