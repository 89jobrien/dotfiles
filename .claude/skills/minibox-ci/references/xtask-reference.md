# xtask Command Reference

Workspace task runner at `xtask/src/main.rs`. Run with `cargo xtask <task>`.

## Gates

### `pre-commit`

fmt-check → clippy → release build. **macOS-safe.**

Crates: `minibox-lib`, `minibox-macros`, `minibox-cli`, `daemonbox`
Excludes: `miniboxd` (has `compile_error!()` on non-Linux)

```bash
cargo xtask pre-commit
```

### `prepush`

nextest → llvm-cov html coverage report.

Crates: same as pre-commit
Output: `target/llvm-cov/html/index.html`

```bash
cargo xtask prepush
```

### `test-unit`

Runs all platform-safe tests. Used in CI.

Steps:
1. `cargo test -p minibox-lib -p minibox-macros -p minibox-cli -p daemonbox --lib`
2. `cargo test -p daemonbox --test handler_tests`
3. `cargo test -p daemonbox --test conformance_tests`

```bash
cargo xtask test-unit
```

### `test-e2e-suite`

Full daemon+CLI end-to-end tests. **Linux + root required.**

Steps:
1. `cargo build --release` (full workspace)
2. Build `miniboxd/tests/e2e_tests` binary without running
3. Re-exec test binary under `sudo -E` with `MINIBOX_TEST_BIN_DIR` set
4. `--test-threads=1 --nocapture`

```bash
cargo xtask test-e2e-suite
```

## Utilities

### `bench`

Runs `target/release/minibox-bench` (dry-run then live). Build release first.

```bash
cargo xtask bench
```

### `clean-artifacts`

Removes compiled binaries from `target/debug` and `target/release` (preserves incremental cache, registry, `.d` dep files). Also removes `.dSYM` bundles on macOS.

```bash
cargo xtask clean-artifacts
```

### `nuke-test-state`

Kills orphan `miniboxd` processes, unmounts test overlays, stops test cgroup scopes, removes `/tmp/minibox-test-*`. Run after interrupted e2e tests.

```bash
cargo xtask nuke-test-state
```

## Test Coverage by Crate

| Crate | `test-unit` | `prepush` | `test-e2e-suite` |
|---|---|---|---|
| minibox-lib | ✓ (--lib) | ✓ | - |
| minibox-macros | ✓ (--lib) | ✓ | - |
| minibox-cli | ✓ (--lib) | ✓ | ✓ (via CLI calls) |
| daemonbox | ✓ (--lib + integration) | ✓ | - |
| miniboxd | - | - | ✓ (e2e_tests) |
