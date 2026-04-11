---
name: devloop-bench-cycle
description: Full benchmark cycle for devloop — collect criterion results, check against budgets, commit the run to SQLite, surface regressions. Use after running cargo bench or when managing performance budgets.
---

# Devloop Bench Cycle

Full workflow for collecting, checking, and committing benchmark results in devloop.

## Prerequisites

- `devloop` binary installed at `~/.local/bin/devloop`
- devloop project is the current working directory (or use `--repo`)

## Step 1 — Run benchmarks

```bash
cd ~/dev/devloop
cargo bench --workspace 2>&1 | tee /tmp/bench-output.txt
```

Criterion outputs JSON results to `target/criterion/`. The bench cycle reads from there.

## Step 2 — Collect results

```bash
devloop bench collect 2>&1
```

This reads criterion output, parses `mean_ns`, `median_ns`, `std_dev_ns`, `ci_lower_ns`, `ci_upper_ns` per benchmark, and saves a run to the SQLite bench store.

If collect fails with "no criterion data": ensure `cargo bench` was run first and `target/criterion/` exists.

## Step 3 — Check against budgets

```bash
devloop bench check 2>&1
```

Output shows regression status per benchmark:
- `✓ STABLE` — within CI bounds of previous run
- `⚠ WARNING` — above previous CI upper bound (statistical regression)
- `✗ REGRESSION` — over budget (`max_ns` exceeded)
- `↓ IMPROVED` — below previous CI lower bound

If regressions are found: **do not commit the run**. Investigate root cause first.

## Step 4 — Review history

```bash
devloop bench history --last 10 2>&1
```

Shows trend per benchmark. Useful for distinguishing noise from real regressions.

## Step 5 — Manage budgets (if needed)

Set a new budget:
```bash
devloop bench budget set <benchmark-name> --max 500ms --warn 400ms
```

List all budgets:
```bash
devloop bench budget list
```

Remove a budget:
```bash
devloop bench budget remove <benchmark-name>
```

Budget values use time units: `100ns`, `1ms`, `500ms`, `2s`.

## Step 6 — Commit results

After a clean check (no regressions):

```bash
git add -A  # bench results are stored in SQLite, not git-tracked directly
git commit -m "bench: collect run on <branch>"
```

If there were regressions that were investigated and accepted:

```bash
git commit -m "bench: collect run — <benchmark-name> regression accepted, reason: <explanation>"
```

## Regression response guide

| Status | Action |
|--------|--------|
| IMPROVED | Note in commit message, check it's not a measurement artifact |
| WARNING (+5–20%) | Investigate — check for recent changes to the hot path |
| WARNING (>20%) | Treat as regression — find root cause before proceeding |
| REGRESSION (over budget) | Block — must fix or explicitly raise the budget with justification |

## Category guidance

Benchmarks are auto-categorized:
- `micro` — < 1ms mean (e.g., pure computation, data structure ops)
- `integration` — >= 1ms mean (e.g., full pipeline runs, I/O-bound ops)

Integration benchmarks get budget enforcement; micro benchmarks use statistical comparison only.
