# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Directory Is

`dotfiles/.claude/` is the dotfiles-managed layer of Claude Code config. Files here are candidates for symlinking into `~/.claude/` via GNU Stow — add `.claude` to `config/stow-packages.txt` to activate.

**Do not stow `settings.json`** — it's managed by `scripts/setup-ai-tools.sh`. Safe to stow: statusline scripts, `skills/`, CLAUDE.md files.

## Statusline Scripts

Statusline scripts receive JSON on stdin and write ANSI output. Key fields:

```json
{
  "context_window": { "used_percentage": 42, "remaining_percentage": 58 },
  "cost": { "total_cost_usd": 0.12 },
  "model": { "display_name": "claude-sonnet-4-6" },
  "workspace": { "current_dir": "/path/to/dir" }
}
```

Activate in `~/.claude/settings.json`:
```json
"statusLine": { "type": "command", "command": "bash ~/.claude/statusline-command.sh" }
```

Test locally:
```bash
echo '{"context_window":{"used_percentage":42,"remaining_percentage":58},"cost":{"total_cost_usd":0.12},"model":{"display_name":"claude-sonnet-4-6"},"workspace":{"current_dir":"/Users/joe/dotfiles"}}' | bash statusline-dotfiles.sh
```

The `statusLine` key is not managed by `setup-ai-tools.sh` — add it manually or extend the `configure_claude_code()` jq filter.
