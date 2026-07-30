---
name: commit
description: Run pre-commit checks (fmt, clippy, test) then stage, commit, and push with a conventional message
trigger: /commit
tags: [git, rust, workflow]
---

# Commit Skill

Run pre-commit quality gates, then commit and push.

## Steps

1. If in a Rust workspace, run in order — stop and report if any fail:
   - `cargo fmt --all`
   - `cargo clippy --all-targets -- -D warnings`
   - `cargo test --quiet` (or `cargo nextest run` if nextest is available)

2. Run `git status` to identify changed files. Stage only relevant files (not secrets, `.env`, large binaries).

3. Run `git diff --staged` to review what's being committed.

4. Write a conventional commit message:
   - Format: `<type>(<scope>): <description>`
   - Types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`
   - Keep the subject line under 72 characters
   - Add a body if the change is non-obvious

5. Commit with `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>` trailer.

6. Push to the current branch's remote tracking branch.

7. Report the commit hash and pushed ref.

## Rules

- Never skip clippy or tests. If they fail, fix them before committing.
- Never use `--no-verify`.
- Never commit `.env` files, secrets, or `*.local.*` files.
- Do not ask the user to run anything — execute all steps yourself.
