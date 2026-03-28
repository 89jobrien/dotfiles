# Quality Gates

## When to Run What

### Every Commit (macOS-safe)

```bash
cargo xtask pre-commit
```

Runs: `cargo fmt --all --check` + clippy (all macOS-safe crates) + `cargo build --release`

Crates covered: minibox-lib, minibox-macros, minibox-cli, daemonbox, macbox, miniboxd, minibox-llm, minibox-secrets

### Every Push

```bash
cargo xtask prepush
```

Runs: nextest (parallel test runner) + llvm-cov coverage report

### Unit + Conformance Tests

```bash
cargo xtask test-unit       # 257 tests: 155 lib + 11 cli + 22 handler + 16 conformance + 13 llm + 36 secrets + 4 skipped
cargo xtask test-property   # 33 proptest properties (8 daemonbox + 25 minibox-lib)
```

### Linux-Only Tests (VPS or CI)

```bash
just test-integration       # 16 cgroup tests (requires root + cgroups v2)
just test-e2e               # lifecycle e2e (requires root + Docker Hub)
just test-e2e-suite          # 14 daemon+CLI e2e tests (requires root)
just test-all               # full pipeline: nuke → doctor → all tests → nuke
```

### Benchmarks

```bash
just bench                  # run locally, saves to bench/results/
cargo xtask bench-vps       # run on VPS, fetch results
mise run macos:bench        # macOS: start Colima daemon, bench, open report
```

## Clippy — Always Use Explicit `-p` Flags

**Never** use `--workspace`. The canonical clippy invocation:

```bash
cargo clippy -p minibox-lib -p minibox-macros -p minibox-cli -p daemonbox -p macbox -p miniboxd -p minibox-llm -p minibox-secrets -- -D warnings
```

## CI Pipeline

- **GitHub Actions** (macOS): fmt + clippy + test-unit
- **Gitea Actions** (jobrien-vm): `cargo deny check` + `cargo audit` only (no compilation — VPS too small)
- **Local hooks**: pre-commit runs `cargo xtask pre-commit`, pre-push runs `cargo xtask prepush`
