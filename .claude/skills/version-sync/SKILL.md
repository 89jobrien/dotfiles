---
name: version-sync
description: Use before running codegen (baml generate, build.rs, protoc) or when seeing version mismatch errors in generated code. Symptoms - baml client out of date, generated code doesn't compile, version X vs version Y mismatch.
---

# Version Sync

Detect and fix version mismatches between Cargo.toml dependencies and code generator configuration files.

## What This Solves

Generator configs (e.g., `generators.baml`, `buf.gen.yaml`, `build.rs`) pin versions independently from `Cargo.toml`. When these drift — e.g., `baml-lib = "0.218.0"` in Cargo.toml but `version "0.220.0"` in `generators.baml` — the result is silent failures, stale generated code, or runtime panics. The fix cycle is: align versions → regenerate → verify.

## Step 1: Detect Mismatches

Find what Cargo.toml thinks the versions are:

```bash
cargo metadata --no-deps --format-version 1 | jq '.packages[].dependencies[] | select(.name | startswith("baml")) | {name, req}'
```

Find all generator config files that contain version pins:

```bash
fd -e baml -e toml -e yaml | xargs grep -l "version"
```

Read the pinned version inside a `generators.baml` block:

```bash
grep -E 'version\s+"[0-9]' $(fd -e baml)
```

## Step 2: Common Generator Configs

**1. `generators.baml`**

```
generator TypescriptClient {
  output_type typescript
  version "0.220.0"   # <-- this must match baml-lib in Cargo.toml
  ...
}
```

Read it:

```bash
grep -A5 '^generator' generators.baml | grep version
```

**2. `build.rs`**

Look for hardcoded version strings in codegen invocations:

```bash
grep -rn 'version\|codegen\|baml\|protoc' build.rs
```

**3. `buf.gen.yaml`**

```yaml
plugins:
  - name: go
    version: v1.30.0   # <-- version field
```

Read it:

```bash
grep 'version' buf.gen.yaml
```

## Step 3: Fix Strategies

**Option A — Pin Cargo.toml to match generator** (preferred when you want the generator's version):

```bash
cargo add baml-lib@0.220.0  # match generators.baml
```

**Option B — Pin generator to match Cargo.toml** (preferred when you're locked to a Cargo version):

Edit the generator config file to match the Cargo.toml version, then re-run codegen:

```bash
# Edit generators.baml: change version "0.220.0" → version "0.218.0"
baml-cli generate
cargo check
```

**Option C — Update both to latest** (preferred when starting fresh):

```bash
cargo add baml-lib  # or: cargo update baml-lib
# then update generators.baml version field to match the resolved version
cargo metadata --no-deps --format-version 1 | jq '.packages[].dependencies[] | select(.name == "baml-lib") | .req'
```

## Step 4: Verify After Fix

```bash
cargo check 2>&1 | grep -E "error|warning" | head -20
# For BAML:
baml-cli generate  # re-run codegen
cargo check        # confirm generated code compiles
```

## Quick Diagnostic One-liner

Prints Cargo.toml baml versions alongside generator config version pins found in the project:

```bash
echo "=== Cargo deps ===" && \
cargo metadata --no-deps --format-version 1 | jq -r '.packages[].dependencies[] | select(.name | startswith("baml")) | "\(.name): \(.req)"' && \
echo "=== Generator configs ===" && \
fd -e baml -e yaml -e toml | xargs grep -En 'version\s+"[0-9]|version:\s+[0-9v]' 2>/dev/null
```

## Common Failure Table

| Symptom | Cause | Fix |
|---------|-------|-----|
| `version mismatch: expected X got Y` | Cargo.toml != generator config | Align versions (Option A or B) |
| Generated code doesn't compile | Stale generated files | Re-run codegen after version align |
| `baml-cli generate` fails | CLI version != lib version | Install matching baml-cli: `cargo install baml-cli@0.218.0` |
| `cargo build` passes but runtime panics | Generated client is stale | Always regenerate after dep version changes |
| Silent wrong behavior | Mismatched client/server schemas | Verify generated types match current config |
