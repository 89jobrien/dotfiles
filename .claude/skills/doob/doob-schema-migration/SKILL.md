---
name: doob-schema-migration
description: Use before any change to src/db/schema.rs or SurrealDB schema definitions. Symptoms - adding a new field to todo/note, changing an index, adding a new table, or seeing schema-related test failures after a schema edit.
---

# doob: Schema Migration

## Overview

doob's SurrealDB schema is defined in `src/db/schema.rs` and applied on every connection via `define_schema()`. Changes here affect the live database at `~/.claude/data/doob.db`.

## Pre-Migration Checklist

1. Back up the live database
2. Identify all queries affected by the change
3. Verify the change is additive (prefer) or requires data migration
4. Update the schema definition
5. Run tests against a fresh temp DB
6. Smoke-test against the backed-up live DB

## Step 1: Backup

```bash
cp ~/.claude/data/doob.db ~/.claude/data/doob.db.bak.$(date +%Y%m%d-%H%M%S)
ls -lh ~/.claude/data/doob.db.bak.*
```

## Step 2: Classify the Change

| Change type | Risk | Notes |
|---|---|---|
| Add optional field with default | Low | Existing records get default |
| Add required field without default | High | Existing records break |
| Add new index | Low | SurrealDB builds index on existing records |
| Remove field | High | Lost data, query breakage |
| Rename field | High | All queries must be updated |
| Add new table | None | No impact on existing tables |

## Step 3: Additive Pattern (preferred)

```rust
// In schema.rs — add OPTIONAL field with DEFAULT
db.query("DEFINE FIELD external_refs ON TABLE todo TYPE option<array> DEFAULT []").await?;
```

SurrealDB applies defaults to existing records on next read — no data migration needed.

## Step 4: Test Against Fresh DB

```bash
# Tests use tempfile for isolation — run normally
cargo nextest run --all-features

# Verify specific schema test
cargo nextest run -- db
```

## Step 5: Smoke Test Live DB

```bash
# Run against backed-up copy
DOOB_DB_PATH=~/.claude/data/doob.db.bak.<timestamp> doob todo list
```

## Rollback

```bash
# Restore from backup
cp ~/.claude/data/doob.db.bak.<timestamp> ~/.claude/data/doob.db
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Editing schema without backup | Always backup first — schema errors can corrupt records |
| Adding required field to existing table | Always use `TYPE option<T>` with `DEFAULT` |
| Forgetting to update model struct | Schema and `src/models/*.rs` must stay in sync |
| Running `cargo test` (not nextest) | Use `cargo nextest run` — parallel tests need isolation |
