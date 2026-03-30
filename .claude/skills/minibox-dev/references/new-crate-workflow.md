# Adding a New Workspace Crate

## The Pattern (from minibox-llm and minibox-secrets)

The repeated workflow for adding a new crate to the minibox workspace:

### 1. Design Spec

Write a design spec in `docs/superpowers/specs/` with frontmatter:

```markdown
---
status: draft | approved | implemented
---
```

Run council review: `just council main extensive`

### 2. Implementation Plan

Write an implementation plan in `docs/plans/` or `docs/superpowers/plans/`.

### 3. Create the Crate

```bash
cargo new crates/<name> --lib    # or --bin
```

Add to root `Cargo.toml`:

```toml
[workspace]
members = [
    # ... existing members
    "crates/<name>",
]
```

**Critical**: add `license = "MIT"` to the new crate's `Cargo.toml` — `cargo deny check` fails without it.

### 4. Wire Into Quality Gates

Update these files to include `-p <name>`:

| File | What to update |
|---|---|
| `Justfile` → `lint` recipe | Add `-p <name>` to clippy command |
| `Justfile` → `build-release` recipe | Add `-p <name>` if it produces a binary |
| `.github/workflows/ci.yml` | Add `-p <name>` to clippy step |
| `xtask/src/main.rs` | Add to `test-unit` and `pre-commit` crate lists |
| `CLAUDE.md` → "macOS quality gates" | Add `-p <name>` to clippy example |
| `CLAUDE.md` → "Workspace Structure" | Add crate description |
| `HANDOFF.md` → "Crate layout" | Add crate to layout diagram |

### 5. Implement + Test

- Follow hexagonal architecture: domain traits in the crate, adapters as implementations
- Unit tests in `#[cfg(test)] mod tests` within each module
- Use `anyhow::Context` for all error paths — no `.unwrap()` in production
- Run `cargo xtask pre-commit` after each major change

### 6. Council Review

```bash
just council main extensive    # 5-role review of the diff vs main
```

Address P1 (critical) and P2 (important) findings before merging.

### 7. Update Documentation

- Update test counts in `CLAUDE.md` and `HANDOFF.md`
- Add crate to dependency graph in `HANDOFF.md`

## Recent Examples

- **minibox-llm** (2026-03-21): Multi-provider LLM client, 13 commits, FallbackChain pattern
- **minibox-secrets** (2026-03-22): Credential store with provider chain, 2 commits + council fix
