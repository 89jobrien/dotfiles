@RTK.md

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

## Debugging Guidelines

- When debugging, check environment variables and secrets resolution FIRST before investigating code-level causes.
- Common root causes: missing env vars, unresolved op:// refs, wrong PATH/toolchain.

## Development Principles

When implementing changes across multiple files, propose a systemic/architectural solution first (e.g., fallback logic, shared config) rather than per-file repetition. Ask before changing more than 3 files individually.

## GitHub Actions Workflows

The Write tool is blocked by a security hook on `.github/workflows/*.yml` files. Use Bash heredoc instead.

## Reference Repos

`~/dev/minibox` — canonical CI/workflow patterns for Rust projects (ci.yml, nightly.yml, release.yml, deny.toml).

## Git / Commit Signing

Commits are signed via SSH key through the 1Password agent. If `git commit` fails with `1Password: agent returned an error`, open 1Password and unlock it, then retry. No config change needed.

## Active Hooks (transparent, always-on)

- **PreToolUse/Bash**: `rtk-rewrite.sh` — rewrites CLI commands through RTK for token savings
- **PreToolUse/Bash**: `pre-tool-course-correct.py` — blocks anti-pattern Bash commands (grep/cat/find/npm/pip/nvm — use dedicated tools instead); also blocks any Bash command that fails ≥3 times in 5 min. Rules: `~/.claude/hooks/course-correct-rules.json`
- **PostToolUse/Bash**: `post-bash-redact.sh` — redacts sensitive output
- **PostToolUse/Bash**: `post-tool-track-failures.py` — records failed Bash exit codes for course-correct learning
- **PostToolUse/Edit|Write**: `post-edit-cargo-fmt.sh` — auto-runs `cargo fmt` on edited Rust files
- **PostToolUse/Edit|Write**: `sync_memory_to_vault.py` — syncs `~/.claude/…/memory/` files to Obsidian vault

## Secrets Audit

`mise run redact-audit` scans staged files via obfsck and logs findings as JSONL. Add `--verbose` for stderr output. Always exits 0 (non-blocking).

## Memory System

Auto-memory at `~/.claude/projects/-Users-joe--claude/memory/`. Index: `MEMORY.md`. Types: `user`, `feedback`, `project`, `reference`.
