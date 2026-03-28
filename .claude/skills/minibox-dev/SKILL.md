---
name: minibox-dev
description: Use when developing minibox — quality gates, adding crates/adapters, testing strategy, VPS Linux testing, bench ops, and common workflows. Symptoms - need to run tests, add a new crate, wire an adapter, run benchmarks, deploy to VPS, or understand the development workflow.
---

# Minibox Development

## References

- [references/quality-gates.md](references/quality-gates.md) — What to run, when, and where (macOS vs Linux vs VPS)
- [references/new-crate-workflow.md](references/new-crate-workflow.md) — End-to-end workflow for adding a new workspace crate
- [references/adapter-workflow.md](references/adapter-workflow.md) — Adding or modifying hexagonal architecture adapters
- [references/vps-ops.md](references/vps-ops.md) — VPS (jobrien-vm) operations: SSH, bench, Linux testing, Gitea CI
- [references/ecosystem.md](references/ecosystem.md) — Joe's related Rust projects (doob, devloop, obfsck) and how they connect

## Helper Scripts

Available in `sh`, `fish`, and `nu` variants:

| Script | Purpose |
|---|---|
| `helpers/mbx-gate.{sh,fish,nu}` | Smart quality gate — picks tests based on what changed (`--auto`, `--quick`, `--full`) |
| `helpers/mbx-new-crate.{sh,fish,nu}` | Scaffold new workspace crate with all wiring (`mbx-new-crate <name> [--lib\|--bin]`) |
| `helpers/mbx-status.{sh,fish,nu}` | Dev dashboard: crate health, test tools, bench results, VPS reachability, CI status |
| `helpers/mbx-context.{sh,fish,nu}` | Context loader: crate layout, recent commits, branch state (`--brief`, `--full` for adapters/traits/plans) |

Run directly:

```bash
# bash/zsh
~/.claude/skills/mbx/minibox-dev/helpers/mbx-status.sh

# fish
~/.claude/skills/mbx/minibox-dev/helpers/mbx-status.fish

# nushell
nu ~/.claude/skills/mbx/minibox-dev/helpers/mbx-status.nu
```

## Quick Reference

### Quality Gates (macOS — run before every commit)

```bash
cargo xtask pre-commit          # fmt-check + clippy + release build
cargo xtask prepush             # nextest + llvm-cov coverage
cargo xtask test-unit           # unit + conformance (257 tests)
cargo xtask test-property       # proptest (33 properties)
```

### AI Agent Commands

```bash
just council [base] [mode]      # multi-role branch review (core/extensive)
just ai-review [base]           # security/correctness diff review
just meta-agent "task"          # design + spawn parallel agents
just gen-tests <TraitName>      # scaffold adapter unit tests
just diagnose [--container id]  # diagnose container failure
just bench-agent report         # AI bench analysis
just commit-msg [-a] [-c]       # AI-generated commit message
```

### Adding a New Crate

1. `cargo new crates/<name> --lib` (or `--bin`)
2. Add to workspace `members` in root `Cargo.toml`
3. Add `license = "MIT"` to crate's `Cargo.toml` (deny.toml requires it)
4. Add `-p <name>` to clippy/test commands in Justfile, CI, and xtask
5. Run `cargo xtask pre-commit` to verify

### VPS Operations

```bash
mise run all:ssh-vps            # SSH into jobrien-vm
mise run all:bench              # Run benchmarks on VPS (cargo xtask bench-vps)
mise run all:bench:setup        # One-time VPS bench setup
mise run all:ci                 # Check Gitea CI status
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| `cargo test --workspace` on macOS | Fails — use `cargo xtask test-unit` or explicit `-p` flags |
| `cargo clippy --workspace` | Fails on platform-gated code — use explicit `-p` flags from Justfile |
| Missing `license = "MIT"` on new crate | `cargo deny check` fails — add to Cargo.toml |
| Running agent scripts with `python3` | Use `uv run scripts/foo.py` — PEP 723 inline deps |
| Running agent scripts in background | They need interactive terminal — run foreground |
| `cargo check --workspace` passes but clippy fails | `check` is more lenient — always run clippy via `just lint` |
| Editing miniboxd without testing on Linux | Namespace/cgroup code is Linux-only — test via VPS |
