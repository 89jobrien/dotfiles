---
allowed-tools: Bash
argument-hint: ' <id> [YYYY-MM-DD|clear]'
description: Set or clear the due date for a todo using doob CLI.
author: Joseph OBrien
source: 89jobrien/steve
tag: commands
name: due
---

# Set Due Date

Set or clear the due date for a todo in doob.

## Usage

```bash
/todo:due <id> <date>
/todo:due <id> clear
```

## Instructions

1. Parse the todo ID from arguments
2. Convert natural language dates to YYYY-MM-DD:
   - `tomorrow` → next day
   - `next week` → 7 days from now
   - `in 3 days` → 3 days from now
3. Use `clear` to remove an existing due date

## Command

!doob todo due $ARGUMENTS
