---
name: rust-snapshot-review
description: Review and accept/reject insta snapshot changes after cargo nextest runs. Handles the stale .snap.new footgun, shows inline diffs, and does safe bulk or selective acceptance. Use whenever cargo nextest produces .snap.new files.
---

# Rust Snapshot Review

Workflow for reviewing and accepting insta snapshot updates. Guards against the stale-snapshot footgun.

## The Footgun

`.snap.new` files from a PREVIOUS failed run persist until cleaned up. If you accept them instead of the fresh ones, you silently accept stale output. Always check mtime.

## Step 1 — Detect snapshots

```bash
find . -name "*.snap.new" -not -path "*/target/*" 2>/dev/null
```

If empty: nothing to do.

## Step 2 — Validate freshness

Compare mtime of `.snap.new` files against the last nextest run:

```bash
# Proxy: nextest writes to target/nextest/ on each run
find . -name "*.snap.new" -not -path "*/target/*" \
  -newer target/nextest 2>/dev/null
```

If no `.snap.new` files are newer than the last test run: **warn before proceeding**.

```
⚠ Snapshot files may be stale (older than last test run).
  Consider deleting them and re-running tests:
    find . -name "*.snap.new" -not -path "*/target/*" -delete
    _DEVLOOP_OP_WRAPPED=1 cargo nextest run -p <crate> <test>
```

## Step 3 — Review diffs

For each `.snap.new`:

```bash
SNAP="${FILE%.new}"
if [ -f "$SNAP" ]; then
    diff "$SNAP" "$FILE"
else
    echo "[NEW SNAPSHOT]"
    cat "$FILE"
fi
```

Summarize what changed:
- New snapshots: show full content
- Changed: show unified diff, highlight key differences
- If the diff looks like a version bump or timestamp: safe to accept
- If the diff looks like a behavioral change: flag for review

## Step 4 — Accept

**Bulk accept** (after reviewing all):

```bash
for f in $(find . -name "*.snap.new" -not -path "*/target/*"); do
  mv "$f" "${f%.new}"
  echo "Accepted: $f"
done
```

**Selective** — accept one at a time, asking between each.

**Reject** — leave `.snap.new` files in place. The next test run will regenerate them.

## Step 5 — Verify acceptance

Re-run only the tests that use these snapshots:

```bash
_DEVLOOP_OP_WRAPPED=1 cargo nextest run -p <crate> <test_filter>
```

Confirm no `.snap.new` files remain and all tests pass.

## Devloop-specific known snapshots

| Test | Location | Changes when |
|------|----------|--------------|
| `cli_snapshot_test__logs_output_format` | `crates/cli/tests/snapshots/` | Session format changes |
| `cli_snapshot_test__bench_output` | `crates/cli/tests/snapshots/` | Bench output format changes |
| `cli_snapshot_test__help_text` | `crates/cli/tests/snapshots/` | CLI help text changes (new commands) |

**Note:** Tests in `.worktrees/` paths always fail — do NOT add to nextest exclusions. Run them from the main checkout only.

## Quick reference

```bash
# Find pending
find . -name "*.snap.new" -not -path "*/target/*"

# Accept all
for f in $(find . -name "*.snap.new" -not -path "*/target/*"); do mv "$f" "${f%.new}"; done

# Delete stale (nuclear option)
find . -name "*.snap.new" -not -path "*/target/*" -delete
```
