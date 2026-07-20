---
name: "cmd:herald"
description: Synthesize cross-project activity into an Obsidian daily note.
allowed-tools: Bash, Read, Write
argument-hint: '[--repo <name>] [--window <duration>] [--dry-run]'
author: Joseph O'Brien
---

# Herald

Arguments: $ARGUMENTS. Default: all active repos, last 24h, write to Obsidian vault daily note.

1. For each active repo in the allowlist, run: `git -C $HOME/dev/<repo> log --since="24 hours ago" --oneline`
2. Synthesize findings into a narrative summary grouped by project
3. Write to `$HOME/Documents/Obsidian Vault/Daily Notes/$(date +%Y-%m-%d).md` (append if exists)
4. If `--dry-run`, print only — do not write
