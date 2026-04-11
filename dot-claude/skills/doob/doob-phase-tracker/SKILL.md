---
name: doob-phase-tracker
description: Use when assessing which roadmap phase doob is currently in, what's code-complete vs stub vs unstarted, or deciding what to work on next. Use before starting a new phase or when the README roadmap and codebase feel out of sync.
---

# doob: Phase Tracker

## Roadmap Reference

| Phase | Focus | Status signals |
|---|---|---|
| 1 | Hexagonal arch foundation | ✅ Done — `src/sync/domain.rs` exists |
| 2 | Beads adapter | ✅ Done — `src/sync/adapters/beads.rs` exists |
| 3 | Sync metadata repository | `SyncRecord` exists; SurrealDB repo TBD |
| 4 | CLI sync commands | `doob sync to` not yet in `src/cli.rs` |
| 5 | Additional providers | Only Beads exists in `src/sync/adapters/` |

## Phase Assessment Commands

```bash
# Phase 3: check for sync metadata repository
grep -r "SyncRepository\|sync_metadata\|sync_records" src/ --include="*.rs" -l

# Phase 4: check for sync CLI commands
grep -r "sync" src/cli.rs

# Phase 5: count provider adapters
ls src/sync/adapters/

# Overall: check TODOs and unimplemented!() in sync code
grep -rn "todo!\|unimplemented!\|// TODO" src/sync/ --include="*.rs"
```

## What "Code-Complete" Means Per Phase

**Phase 3 complete when:**
- `SyncRepository` trait exists in `src/sync/domain.rs`
- SurrealDB implementation in `src/sync/adapters/surreal_sync_repo.rs`
- `SyncRecord` persisted/retrieved with correct timestamps
- Tests cover: save, load, list-by-provider, list-by-todo-id

**Phase 4 complete when:**
- `doob sync to --provider <name>` runs a sync
- `doob sync status` shows last sync per todo
- `doob sync providers` lists configured providers
- Commands wired in `src/cli.rs` and `src/commands/sync/`

## Quick Gap Report

```bash
# Run this to see what's implemented vs stubbed
cargo doc --no-deps 2>&1 | grep "warning\|TODO"
cargo test 2>&1 | grep "test result"
grep -rn "unimplemented!" src/ --include="*.rs"
```

## Next Phase Decision Rule

Start Phase N+1 only when:
1. All Phase N tests pass (`cargo nextest run`)
2. No `unimplemented!()` in Phase N code paths
3. README reflects Phase N as complete
