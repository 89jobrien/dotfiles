# Joe's Rust Ecosystem

Projects that interact with or complement minibox.

## doob (`~/dev/doob`)

**Agent-first todo CLI** built with Rust + SurrealDB.

- Single binary, no external deps at runtime
- JSON output for agent integration (`doob --json todo list`)
- Context-aware: auto-detects project/file from git
- Hexagonal architecture (same pattern as minibox): `IssueTracker` trait with provider adapters
- DB at `~/.claude/data/doob.db`
- Skills: `todo:add`, `todo:list`, `todo:complete`, `todo:undo`, `todo:due`, `todo:remove`

**Relevance to minibox**: Used for task tracking across sessions. When breaking minibox work into discrete steps, doob captures them.

## devloop (`~/dev/devloop`)

**Development observability tool** — Ratatui TUI + CLI for git history and Claude session analysis.

- Visualizes git commits + Claude AI session activity per branch
- Council analysis (multi-role AI review) of branches
- Code structure analysis via GKG integration
- Installed globally at `~/.local/bin/devloop`
- Skills: `using-devloop`, `devloop-standup`, `devloop-daily-update`

**Relevance to minibox**: Primary tool for understanding what happened across sessions. `devloop analyze --repo ~/dev/minibox` gives AI-powered branch analysis. Session logs at `~/.claude/projects/-Users-joe-dev-minibox/`.

## obfsck (`~/dev/obfsck`)

**Secret redaction and log obfuscation** library + CLI.

- Replaces secrets with labeled tokens (`[REDACTED-AWS-KEY]`)
- Stable identifier mapping (same input → same token)
- Three privacy levels: Minimal, Standard, Paranoid
- Feature-gated: core lib has zero optional deps; `analyzer` feature adds full CLI/API
- Binaries: `redact`, `analyzer`, `api` (all require `analyzer` feature)

**Relevance to minibox**: Could be used for sanitizing container logs or daemon output before sharing. Not currently integrated.

## Shared Patterns

All four projects share:

| Pattern | Details |
|---|---|
| Hexagonal architecture | Domain traits as ports, adapters as implementations |
| `mise.toml` for task running | Human-facing tasks |
| Conventional commits | `feat(scope):`, `fix(scope):`, `docs:`, `refactor:` |
| `anyhow` for errors | `.context()` everywhere, no `.unwrap()` in production |
| CI via GitHub Actions | fmt + clippy + tests |
| 1Password for secrets | `op` CLI for credential access |
