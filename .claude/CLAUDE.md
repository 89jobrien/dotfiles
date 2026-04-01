@RTK.md

## Communication Style

- Be direct and concise. Lead with the answer or action, not the reasoning.
- Do not over-explain. Skip filler words, preamble, and unnecessary transitions.
- Do not restate what was just done — the diff is visible.
- Avoid sycophantic openers ("Great question!", "Absolutely!", "Sure!").
- One sentence is better than three when both say the same thing.

## General Behavior

- When asked to fix something, fix it directly. Do not tell the user to fix it themselves unless explicitly asked for instructions only.

## File Paths & Environment

- Always resolve file paths relative to $HOME (not ~) when referencing dotfiles, secrets, or config files outside the project directory.
- Use $HOME expansion in scripts, not tilde.

## Subagents / Task Agents

- After subagents complete work, always verify their changes were committed. Subagents frequently complete tasks but fail to commit.

## Secrets & Environment Variables

- Claude's shell context cannot resolve `op://` URIs directly. Use `op read` for individual secrets or `op run` to inject them into a command's environment. Never assume direnv resolves `op://` references in Claude's context.
- Never pass raw op:// URIs to commands that expect actual values.

## Testing & Validation

- Primary languages: Rust (cargo, clippy, cargo-deny), Python, Shell (nu)
- Always run `cargo clippy` and `cargo test` after Rust changes.
- Run tests before committing.
- Do not investigate rust-analyzer or IDE diagnostics unless explicitly asked — they are often stale and not real issues.

## Debugging Guidelines

- When debugging, check environment variables and secrets resolution FIRST before investigating code-level causes.
- Common root causes: missing env vars, unresolved op:// refs, wrong PATH/toolchain.

## Development Principles

When implementing changes across multiple files, propose a systemic/architectural solution first (e.g., fallback logic, shared config) rather than per-file repetition. Ask before changing more than 3 files individually.

## GitHub Actions Workflows

The Write tool is blocked by a security hook on `.github/workflows/*.yml` files. Use Bash heredoc instead.

## Reference Repos

`~/dev/minibox` — canonical CI/workflow patterns for Rust projects (ci.yml, nightly.yml, release.yml, deny.toml).

## Git Operations

- When asked to commit and push, do it immediately without asking clarifying questions. Use `git add -A && git commit -m "<descriptive message>" && git push` unless told otherwise.
- Never rebase branches that contain merge commits. Use `git merge` for conflict resolution unless explicitly told to rebase.
- Do not scope work beyond what is explicitly requested. If asked to update one file, only touch that file.

## Git / Commit Signing

Commits are signed via SSH key through the 1Password agent. If `git commit` fails with `1Password: agent returned an error`, open 1Password and unlock it, then retry. No config change needed.

## Active Hooks (transparent, always-on)

- **PreToolUse/Bash**: `rtk-rewrite.sh` — rewrites CLI commands through RTK for token savings
- **PreToolUse/Bash**: `pre-tool-course-correct.py` — blocks anti-pattern Bash commands (grep/cat/find/npm/pip/nvm — use dedicated tools instead); also blocks any Bash command that fails ≥3 times in 5 min. Rules: `~/.claude/hooks/course-correct-rules.json`
- **PostToolUse/Bash**: `post-bash-redact.sh` — redacts sensitive output
- **PostToolUse/Bash**: `post-tool-track-failures.py` — records failed Bash exit codes for course-correct learning
- **PostToolUse/Edit|Write**: `post-edit-cargo-fmt.nu` — auto-runs `cargo fmt` on edited Rust files
- **PostToolUse/Edit|Write**: `post-edit-cargo-check.nu` — runs `cargo check --workspace` after Rust edits, surfaces errors to stderr (non-blocking)
- **PostToolUse/Edit|Write**: `sync_memory_to_vault.py` — syncs `~/.claude/…/memory/` files to Obsidian vault

## Secrets Audit

`mise run redact-audit` scans staged files via obfsck and logs findings as JSONL. Add `--verbose` for stderr output. Always exits 0 (non-blocking).

## Memory System

Auto-memory at `~/.claude/projects/-Users-joe--claude/memory/`. Index: `MEMORY.md`. Types: `user`, `feedback`, `project`, `reference`.

## Rules

### General
- Do not modify or audit files outside the specifically requested scope. 
- If asked to update CLAUDE.md for minibox, only touch minibox's CLAUDE.md.

### CI/CD

- When editing workflow files (.github/workflows/), use Bash heredocs instead of the Edit tool, as Edit is often blocked for these files.

## Identity

Full name for copyright/license attribution: Joseph O'Brien
GitHub account: `89jobrien`

## GitHub / Publishing

Create public repos: `gh repo create 89jobrien/<name> --public --description "..."`
Add as second remote: `git remote add github https://github.com/89jobrien/<name>.git`

For dual MIT/Apache-2.0 licensing in Rust workspaces:
- Use `[workspace.package] license = "MIT OR Apache-2.0"` + `license.workspace = true` in each crate
- Do NOT use curl for Apache license text — RTK truncates it. Write the full text directly.

## Rust Development
- After Rust code changes:
  - always run `cargo check` before committing. 
  - If clippy warnings exist, fix them proactively. 
  - Run `cargo test` if test files were modified.
- Do not investigate rust-analyzer or IDE diagnostics unless explicitly asked. They are often stale and not real issues.

## Nushell

Primary shell is Nushell (`nu`). Key syntax differences from POSIX shells:

- `const` cannot reference `$env` — use `let` or read env vars at runtime with `$env.VAR`
- `&&` is not valid in aliases or pipelines — use `;` to chain commands, or newlines
- String interpolation has paren-parsing quirks: `$"text ($expr) more"` — the parens are required
- Stdin handling differs from POSIX: use `open --raw /dev/stdin` to read stdin in scripts
- `do { ... } | complete` captures both stdout and exit code — use this for fallible commands
- Shebang for scripts: `#!/usr/bin/env nu`
- Always test nu syntax with `nu -c '<snippet>'` before writing to a file
- Hook scripts read Claude tool input from stdin as JSON: `open --raw /dev/stdin | from json`

## Cross-Compilation

- Always verify target triple matches deployment environment before building
- Local macOS dev machine: `aarch64-apple-darwin`
- Deployment target for minibox/VPS: `x86_64-unknown-linux-musl`
- Never rsync a binary before verifying it was built for the correct target
- Use `file <binary>` to confirm architecture after cross-compile
- Do not use Colima or Docker Desktop for Linux container work — use minibox (`mbx`)

## Subagent Guardrails

When dispatching subagents:

- Explicitly pass `--allowedTools` — subagents do NOT inherit Bash permissions from parent
- Each subagent must verify `git status` shows a clean worktree before running tests
- Never use octopus merges across subagents — cherry-pick sequentially if branches diverge
- After subagents complete, always verify their changes were committed (`git log --oneline -3`)
- Cap parallel subagents at 5 concurrent to avoid API rate limits

## Minibox / mbx

- Crate formerly called `linuxbox` was renamed to `mbx` on 2026-03-29 — any `linuxbox::` reference is stale
- Workspace uses lib+bin structure: `mbx` is a library crate, `miniboxd`/`minibox-cli` are binaries
- Integration tests access internal modules via the lib crate (`mbx`), not the binary
- Use `minibox` for the project name, `mbx` for the core library crate name
- Rust edition: 2024 — `set_var`/`remove_var` require `unsafe {}`, match ergonomics differ
- Pre-commit gate (macOS): `cargo xtask pre-commit` (fmt-check + clippy + release build)
- Do NOT use Colima as a substitute for minibox in tests or local dev