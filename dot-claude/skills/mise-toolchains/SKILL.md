---
name: mise-toolchains
description: Use when debugging runtime version issues, toolchain not found errors, or version conflicts across projects. Symptoms - wrong node/rust/python/go version active, mise shim errors, RUSTUP_TOOLCHAIN conflicts, tool not found after install, global version overriding project version.
---

# mise Toolchains

## Overview

mise manages language runtimes (Rust, Node, Python, Go, uv) via `.mise.toml` files. **Two config layers interact** — this is the most common source of toolchain confusion:

| File | Scope |
|------|-------|
| `<repo>/.mise.toml` | Project-local runtimes + tasks |
| `~/.config/mise/config.toml` | Global — pins override project entries silently |

**When a toolchain behaves unexpectedly, check global config first.**

## Debugging Toolchain Issues

```bash
# Step 1: What versions are actually active?
mise current

# Step 2: Global overrides?
cat ~/.config/mise/config.toml

# Step 3: Conflicts, missing tools
mise doctor

# Step 4: Ensure installed
mise install

# Step 5: Env var overrides?
printenv | grep -i mise
```

### Rust-Specific

mise sets `RUSTUP_TOOLCHAIN` so cargo uses the right version:

```bash
echo $RUSTUP_TOOLCHAIN     # should match .mise.toml rust version
mise which cargo            # confirm shim resolves correctly
rustc --version             # verify
```

## Common Operations

```bash
mise install                # install all tools from .mise.toml
mise current                # show active versions in cwd
mise ls                     # list installed versions
mise ls --current           # active version per tool
mise which <binary>         # show path a shim resolves to
mise use rust@1.84          # set version in .mise.toml
mise use -g node@22         # set global version
```

## Task Runner

`.mise.toml` doubles as a task runner (`[tasks.<name>]` sections with `run`, `description`, `depends`). Three equivalent runners:

```bash
mise run <task>     # interactive / default
just <recipe>       # automation / agents
make <target>       # compat wrapper
```

```bash
mise tasks           # list tasks
mise run menu        # interactive TUI task picker
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Project version wrong despite `.mise.toml` | Check `~/.config/mise/config.toml` for global override |
| Tool not found after `mise install` | Reload shell: `exec $SHELL` or open new terminal |
| `cargo` uses wrong toolchain | `RUSTUP_TOOLCHAIN` set by mise — check `mise current` |
| Task not found | Check spelling; tasks live in `.mise.toml`, not `mise.local.toml` |
| `mise run` fails with env error | `mise.local.toml` (gitignored) for machine-specific env overrides |
