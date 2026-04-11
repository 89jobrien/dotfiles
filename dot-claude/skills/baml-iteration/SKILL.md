---
name: baml-iteration
description: Structured BAML schema edit → validate → test loop for the devloop project. Use when editing any *.baml file in crates/baml/baml_src/ — covers version parity gotchas, uvx invocation, regeneration workflow, and the analyze verify step.
---

# BAML Iteration

Structured workflow for editing BAML schemas in devloop. Follows the known gotchas from CLAUDE.md so you don't re-derive them each session.

## Before You Edit

Check version parity (the known footgun):

```bash
grep 'version' crates/baml/baml_src/generators.baml  # should say "0.220.0" (cosmetic)
grep 'baml' crates/baml/Cargo.toml | grep version    # should say "0.218.0" (actual)
```

This mismatch is intentional. Only regenerate if Cargo.toml version > generators.baml version.

Check if client is already stale before editing:

```bash
find crates/baml/baml_src -name "*.baml" -newer crates/baml/baml_client/baml_source_map.rs 2>/dev/null
```

## The Edit Loop

### 1. Edit the schema

Make your change in `crates/baml/baml_src/`.

Common files:
- `clients.baml` — LLM client definitions and fallback strategies
- `branch_insights.baml` — Branch analysis function schemas
- `council_insights.baml` — Council synthesis schemas
- `generators.baml` — Code generation config (don't edit version field)

### 2. Quick compile check (no regeneration needed for most edits)

```bash
cargo check -p devloop-baml 2>&1 | grep -E "^error" | head -10
```

If no errors: the existing generated client is still valid for compile. Proceed to test.

If errors mentioning generated code: regenerate (Step 3).

### 3. Regenerate client (only when needed)

**Important**: Temporarily set generators.baml version to "0.218.0":

```bash
# Edit generators.baml: change "0.220.0" → "0.218.0"
cd crates/baml && uvx --from baml-py@0.218.0 baml-cli generate
# Edit generators.baml: restore "0.218.0" → "0.220.0"
```

**Use `uvx`, not `npx`** — mise routes npx through bunx with no default version and it fails.

Verify regeneration:

```bash
git diff --stat crates/baml/baml_client/
cargo check -p devloop-baml
```

### 4. Run affected tests

```bash
_DEVLOOP_OP_WRAPPED=1 cargo nextest run -p devloop-baml 2>&1 | tail -20
```

Note: `devloop-baml` tests require API keys. If no keys available, skip to analyze step.

### 5. Verify with devloop analyze

```bash
env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY \
  op run --account=my.1password.com --env-file=$HOME/.secrets -- \
  devloop analyze --repo $(git rev-parse --show-toplevel)
```

Or via mise: `mise run analyze` (from devloop project root).

Check that the analysis output matches your schema changes.

## Commit Checklist

Before committing BAML changes:

- [ ] `cargo check -p devloop-baml` passes
- [ ] If regenerated: `baml_source_map.rs` is staged along with schema changes
- [ ] generators.baml version is restored to `"0.220.0"`
- [ ] No Ollama clients in default fallback pools (security: unauthenticated HTTP)

## Common Errors

**`error: client not found`** — Function references a client that doesn't exist in clients.baml. Check spelling and that the client is defined.

**`error: type mismatch`** — Return type in BAML function doesn't match the Rust struct. Check `baml_client/types.rs`.

**BAML analyze output looks wrong but compiles** — Prompt in the function body is the issue, not the schema. Edit the `prompt {}` block.

**`npx baml-cli: command not found`** — Use `uvx --from baml-py@0.218.0 baml-cli generate` instead.
