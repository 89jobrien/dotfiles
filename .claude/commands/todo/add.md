---
allowed-tools: Bash
argument-hint: ' <description> [--priority <n>] [-p <project>] [-t <tags>]'
description: Add a todo using doob CLI.
author: Joseph OBrien
source: 89jobrien/steve
tag: commands
name: add
---

# Add Todo

Add a new todo to doob.

!doob todo add $ARGUMENTS

## Examples

```bash
doob todo add "Fix overlay mount pivot_root ordering" --priority 2 -p /Users/joe/dev/minibox -t "bug,filesystem"
doob todo add "Implement parallel layer pulls" --priority 1 -p /Users/joe/dev/minibox -t "feature"
```
