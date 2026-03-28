---
name: rust-conventions
description: Use when working on any Rust crate or workspace — before implementing features, after editing .rs files, when adding or removing dependencies, or when CI is failing. Symptoms - clippy warnings treated as errors, fmt diff in CI, wrong edition error, workspace member not found, slow test runs.
---

# Rust Conventions

## Overview

Conventions for all Rust projects: dotfiles/toolz, Braid crates, Maestro, companion crates (personal-mcp, obfsck). Apply consistently — CI enforces these as hard failures.

## Edition

Always **edition = "2024"** unless explicitly told otherwise. Verify before implementing:

```bash
grep 'edition' Cargo.toml
```

## Quality Gates

Run after **every** code change. CI enforces these as errors:

```bash
# Single crate
cargo fmt --check
cargo clippy -- -D warnings
cargo test

# Workspace
cargo fmt --all --check
cargo clippy --workspace -- -D warnings
cargo test --workspace
```

Use `cargo-nextest` for faster parallel test runs:

```bash
cargo nextest run              # all tests
cargo nextest run -p <crate>   # single crate
```

## Before Removing a Dependency

Verify nothing references it first — removing a used dep breaks the build silently until `cargo check`:

```bash
grep -r "use <crate_name>" src/
grep -r "<crate_name>::" src/
# Then remove from Cargo.toml and:
cargo check
```

## Workspace Structure

```
workspace/
  Cargo.toml          # [workspace] members = ["crate-a", "crate-b"]
  crate-a/
    Cargo.toml        # [package] + [dependencies]
    src/
```

When adding a new crate, add it to `[workspace] members` in the root `Cargo.toml`.

```bash
# Check current members
cargo metadata --no-deps --format-version 1 | jq '.workspace_members'
```

## Per-Crate Operations

```bash
cargo build -p <crate>
cargo test -p <crate>
cargo clippy -p <crate> -- -D warnings
cargo fmt -p <crate>
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Wrong edition | Set `edition = "2024"` in `[package]` |
| `clippy` passes locally but CI fails | Run with `-- -D warnings` to match CI |
| Removed dep still referenced | Grep usages before editing `Cargo.toml` |
| `cargo test` slow | Use `cargo nextest run` |
| New crate not found in workspace | Add to `[workspace] members` in root `Cargo.toml` |
| fmt diff in CI | Run `cargo fmt --all` before committing |
| `fastembed`/ONNX first build slow | Expected — transitive ONNX deps; not a hang |

## Related Skills

- `rust-unsafe-env-mutation` — `set_var`/`remove_var` unsafe + Mutex guard pattern for Rust 2024 tests
- `async-sync-bridge` — `spawn_blocking` + `SyncIoBridge` + `Handle::current()` for async/sync I/O mixing
- `transparent-reader` — pass-through `Read` wrapper for in-flight hashing/counting on streams
