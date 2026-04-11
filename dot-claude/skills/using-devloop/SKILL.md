---
name: using-devloop
description: Use when needing development context — devloop visualizes git commit history and Claude AI session activity for any repo. Available globally via ~/.local/bin/devloop.
args: "[--council] [get context]"
---

# Using Devloop as a Tool

## Overview

Devloop is a development observability tool — a Ratatui TUI plus CLI subcommands for visualizing git commit history and Claude AI session activity. It reads git history and `~/.claude/projects/<project>/` transcript files.

**Don't use raw `git log` when asked to "use devloop."** Use the TUI or CLI subcommands below.

## Installation

The `devloop` binary is installed at `~/.local/bin/devloop`. It's a single unified binary that serves as both TUI and CLI tool.

There's also `~/.local/bin/devloop-relay` for WebSocket relay functionality.

## Default Behavior

When this skill is invoked without arguments, run `devloop analyze` for the current repo. **Always check GKG health first** — running analyze with a broken GKG silently produces "No code structure data available" and half the analysis is useless.

### Pre-flight: Check GKG State

```bash
# Check for stale lock or WAL files before analyzing
ls ~/.gkg/gkg.lock 2>/dev/null && echo "STALE LOCK — remove it"
ls ~/.gkg/gkg_workspace_folders/*/*/database.kz.wal 2>/dev/null && echo "STALE WAL — remove it"
```

If stale files exist, clean up first:

```bash
rm -f ~/.gkg/gkg.lock
rm -f ~/.gkg/gkg_workspace_folders/*/*/database.kz.wal
```

Then run analyze:

```bash
devloop analyze --repo /path/to/repo
```

This provides a quick AI-powered analysis of the current branch activity. If code structure data still shows as unavailable after cleanup, the GKG index may need to be rebuilt — see the GKG Integration section below.

## Skill Arguments

When this skill is invoked with `--council`, run devloop in council mode for deep multi-perspective analysis:

```bash
devloop analyze --council --council-mode extensive --repo /path/to/repo
```

This provides a more thorough, multi-angle analysis of the repository state. Use it when the user wants a comprehensive review rather than a quick status check.

## TUI (Interactive)

```bash
devloop                        # Start interactive TUI for current repo
devloop --repo /path/to/repo   # Start TUI for a specific repo
devloop --offline              # No WebSocket connection
```

The TUI shows: branch list → branch detail → timeline of commits + Claude sessions.

When working in the devloop project itself, you can also use:
```bash
just run          # Start interactive TUI
just dev          # Debug build
just run-debug    # With RUST_LOG=debug
```

## CLI Subcommands

```bash
# View Claude session logs
devloop logs --limit 20                        # Recent sessions for current repo
devloop logs --session <SESSION_ID>            # Specific session
devloop logs --repo /path/to/repo --limit 10   # Different repo

# Export timeline data to JSON
devloop export                                 # Export to devloop-export.json
devloop export -o timeline.json                # Custom output path
devloop export --repo /path/to/repo            # Different repo

# AI analysis (requires API keys)
devloop analyze --repo /path/to/repo           # Analyze branch activity
devloop analyze-session --session <ID>         # Analyze specific Claude session

# Code structure
devloop map --repo /path/to/repo               # Show code map
devloop search --repo /path/to/repo            # Search code definitions

# Benchmarks and examples
devloop bench                                  # Run benchmarks
devloop example                                # Run examples

# Code metrics
devloop gkg-metrics                            # View GKG code structure metrics
```

## What Devloop Reads

| Data | Source |
|------|--------|
| Commits | Git repository history (all local branches) |
| Claude sessions | `~/.claude/projects/<project-path>/*.jsonl` transcripts |
| Branch attribution | Each commit attributed to most-specific branch (feature > main) |

Sessions show errors or empty results if no Claude transcripts exist for the project path.

## AI Analysis Needs Secrets

API keys in `/Users/joe/dev/devloop/.env` are 1Password references (`op://...`) — they must be resolved via `op run` before use.

```bash
# From devloop project — justfile wraps with op run automatically:
just analyze
just analyze-council
just devloop-analyze ~/dev/pieces-ob   # analyze any repo by path

# Direct CLI use — always use personal account with $HOME/.secrets (full path, not ~):
env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY op run --account=my.1password.com --env-file=$HOME/.secrets -- devloop analyze --repo /path/to/repo
env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY op run --account=my.1password.com --env-file=$HOME/.secrets -- devloop analyze --repo /path/to/repo --council
```

## Quick Reference

```bash
# "Show me what's been happening" (interactive)
devloop --repo /path/to/repo

# "Show me what's been happening" (non-interactive)
devloop export --repo /path/to/repo -o /dev/stdout

# "View recent Claude sessions"
devloop logs --repo /path/to/repo --limit 20

# "Show code structure"
devloop map --repo /path/to/repo
```

## GKG Integration

`devloop` and `gkg` complement each other — devloop tracks *activity* (commits, sessions), gkg tracks *structure* (code graph).

Before deep codebase exploration, index with gkg first:

```bash
gkg index ~/dev/some-repo    # refresh the knowledge graph
devloop gkg-metrics          # view code structure metrics via devloop
```

Use `gkg` when you need workspace-wide code search across multiple repos. Use `devloop` when you need to understand what changed and when.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Using `git log` when asked to "use devloop" | Use `devloop` TUI or CLI subcommands |
| Running `cargo run -p devloop-cli-tool` outside devloop project | Use `~/.local/bin/devloop` — it's installed globally |
| Running analyze without API keys | Provide keys via environment or `op run` |
| Expecting Claude sessions when none exist | Only present if `~/.claude/projects/<path>/` has JSONL files |
| Forgetting `--repo` flag | Without it, devloop uses current directory as the repo |
| Running analyze without checking GKG health | Stale `.kz.wal` or `gkg.lock` → silently produces "No code structure data available"; check and clean up first |
