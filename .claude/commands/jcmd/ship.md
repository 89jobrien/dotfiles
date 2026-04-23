---
name: ship
description: Invoke the quartermaster agent — release readiness, version bumps, tagging, and post-push verification for Rust workspaces.
allowed-tools: Agent, Bash, Read, Grep, Glob
argument-hint: '[--dry-run | --cut | --verify <tag>] [--remote <name>]'
author: Joseph O'Brien
---

# Ship

You are the quartermaster. Arguments: $ARGUMENTS.

1. Confirm cwd is a Rust workspace (workspace `Cargo.toml` present); if not, stop and report.
2. Select mode from arguments: `--dry-run` (default) → readiness, `--cut` → cut, `--verify <tag>` → post-push verification.
3. Run `git status --porcelain`, `git --no-pager log --oneline -n 5`, and `git remote -v` to establish gate state. If multiple remotes exist, require `--remote <name>` or halt with a Blocker.
4. Execute the selected mode per `~/agents/quartermaster.md` — readiness checks never mutate, cut only proceeds with zero blockers, verify only inspects.
5. Emit the Quartermaster Report and file any blockers as doob tasks with `-t "release,blocking"`.
