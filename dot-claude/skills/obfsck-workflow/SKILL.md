---
name: obfsck-workflow
description: Structured workflow for obfsck feature work — covers ObfuscationLevel logic, config/secrets.yaml group gating, the PII min_level invariant, and the TDD loop for adding patterns or flags. Use when implementing any obfsck feature from the backlog.
---

# obfsck Workflow

Structured guide for implementing features in `~/dev/obfsck`. Encodes the mental model so you don't re-read `src/lib.rs` from scratch each time.

## Mental Model

### ObfuscationLevel hierarchy

```
Minimal  ← secrets only (API keys, tokens, private keys)
Standard ← + IPs, emails, containers, usernames, PII
Paranoid ← + paths, hostnames, high-entropy strings
```

Default in CLI: `--level minimal`

### Two obfuscation layers

1. **YAML pattern layer** (`config/secrets.yaml`) — regex patterns grouped by category
   - Groups have `enabled` flag and optional `min_level` field
   - Patterns have `paranoid_only: true/false`
   - Applied first in `redact.rs` main()

2. **Structural layer** (`src/lib.rs` `Obfuscator::obfuscate()`) — regex-based structural patterns
   - IPs, emails, container names, user paths, hostnames
   - Level-gated in the match arm on `ObfuscationLevel`
   - Applied second via `obfuscate_text()`

### PII gating invariant

**PII YAML patterns**: `min_level: standard` → only fire at Standard or Paranoid
**Structural emails/IPs**: only fire at Standard or Paranoid in `obfuscate_text()`

**At `--level minimal`: PII is untouched.** This is a load-bearing invariant. Tests must assert it.

## Backlog item reference

| Priority | Item |
|----------|------|
| P100 | `--pii off` flag / explicit level-gating for PII; tests for minimal invariant |
| P75  | Fix username regex `\w+` → `[A-Za-z0-9._-]+` |
| P50  | Integration tests for redact CLI file I/O |
| P50  | Narrow GitHub secret-scanning ignore rules |
| P25  | Combine UUID + hex scans into one pass |
| P25  | Streaming I/O + cached regex |
| P25  | Golden/snapshot tests for demo fixtures |
| P25  | Document new CLI flags in README |

## Workflow for any feature

### 1. Orient

```bash
cd ~/dev/obfsck
cargo test 2>&1 | tail -10   # baseline
cat src/lib.rs | grep -A5 "pub enum ObfuscationLevel"
cat src/bin/redact.rs | head -50
```

### 2. TDD — write the test first

For a new flag or behavior, add to the appropriate test file:
- Unit tests: inline `#[cfg(test)]` in `src/lib.rs` or near the struct
- Integration tests: `tests/` directory
- Golden tests: `tests/golden_tests.rs` (see obfsck-test-harness agent)

Run the test to confirm it fails:
```bash
cargo test <test_name> 2>&1
```

### 3. Implement

Common patterns:

**Adding a CLI flag** (`src/bin/redact.rs`):
```rust
#[arg(long, default_value = "true")]
pii: bool,
```
Then thread the flag through to the pattern filter.

**Adding level gating to a group** (`config/secrets.yaml`):
```yaml
groups:
  my_group:
    enabled: true
    min_level: standard  # add this
```

**Adding level gating in lib.rs**:
```rust
ObfuscationLevel::Minimal => {
    // only secrets
}
ObfuscationLevel::Standard | ObfuscationLevel::Paranoid => {
    // add PII patterns here
}
```

### 4. Verify level invariants

Always run these after any change touching levels:

```bash
# PII untouched at minimal
echo "name = Jane Smith\nphone = (415) 555-1234" | \
  cargo run --bin redact -- --level minimal | \
  grep -E "REDACTED-PII|REDACTED-PHONE|REDACTED-SSN" && \
  echo "FAIL: PII leaked at minimal" || echo "PASS: PII untouched at minimal"

# PII redacted at standard
echo "name = Jane Smith\nphone = (415) 555-1234" | \
  cargo run --bin redact -- --level standard | \
  grep "REDACTED" && echo "PASS" || echo "FAIL: PII not redacted at standard"
```

### 5. Run full suite

```bash
cargo test --workspace 2>&1
```

### 6. Update README if adding a new flag

`README.md` — add to the flags table. Keep it brief.

## Key files

| File | Purpose |
|------|---------|
| `src/lib.rs` | `ObfuscationLevel`, `Obfuscator::obfuscate()`, structural patterns |
| `src/bin/redact.rs` | CLI: arg parsing, YAML config loading, pattern application |
| `config/secrets.yaml` | YAML pattern groups with `min_level` and `paranoid_only` |
| `src/yaml_config.rs` | `SecretsConfig`, `Group`, `PatternDef`, `MinLevel` structs |
| `tests/` | Integration and golden tests |
