---
name: "cmd:ideate"
description: Cross-check plan/spec docs against git log to find stale status markings. Flags plans marked 'done' with no matching commits, and plans marked 'open' that appear to have already landed.
allowed-tools: Bash, Read, Glob, Grep
argument-hint: '[repo-path]'
author: Joseph O'Brien
tag: commands
---

## Configuration

Before running, confirm or substitute these values:

| Variable          | Default / Example                          |
| ----------------- | ------------------------------------------ |
| `PLANS_DIR`       | `docs/plans/`                              |
| `SPECS_DIR`       | `docs/specs/`                              |
| `REPO_ROOT`       | `/path/to/your/repo`                       |
| `HANDOFF_FILE`    | `HANDOFF.md` (relative to `REPO_ROOT`)     |
| `WORKSPACE_FILE`  | `HANDOFF.workspace.yaml` (optional)        |
| `GIT_SINCE`       | `2026-01-01` (start of project history)    |
| `LOG_FILE`        | `~/.local/automation-runs.jsonl`           |
| `SCRIPT_NAME`     | `plan-audit`                               |

---

## Step 1 — Inventory all plan and spec files with their status

Use Glob to find all `.md` files in `PLANS_DIR` and `SPECS_DIR`.

For each file, read the first 10 lines and extract the `status:` field from YAML
frontmatter. Group results into four buckets: `done`, `open`, `superseded`, `missing`
(no status field found).

Print a compact inventory table: filename | status | title (from `title:` or `#` heading).

---

## Step 2 — Audit `status: done` plans for commit evidence

For each plan with `status: done`:

1. Read the first 30 lines to extract 1–3 short search keywords from the title or
   `deliverables:` / `summary:` fields. Prefer concrete nouns: feature names, module
   names, or subsystem names. Keep each keyword to 1–2 words.

2. For each keyword, run:

   ```bash
   git -C <REPO_ROOT> log --oneline --since="<GIT_SINCE>" | grep -i "<keyword>"
   ```

3. If **no keyword** returns any matching commits, flag the plan as **suspicious-done**
   (marked done but no evidence in git log).

4. If at least one keyword matches, record the most recent matching commit SHA+message
   as evidence and mark as **confirmed**.

---

## Step 3 — Audit `status: open` plans for accidental completion

For each plan with `status: open`:

1. Same keyword extraction as Step 2.

2. Run the same git log grep for each keyword.

3. If **any keyword** returns 2 or more matching commits, flag the plan as
   **suspicious-open** (may have already landed).

4. Record the matching commit SHAs as evidence.

---

## Step 4 — Cross-check against handoff files

Read `<REPO_ROOT>/<HANDOFF_FILE>` (full file). Scan for:

- Tasks or blockers listed as open/pending
- Tasks listed as completed

For each open blocker in the handoff file, check whether a plan file covers it and
whether that plan is marked `done`. Flag inconsistencies where the handoff says open
but the plan says done, or vice versa.

If `<WORKSPACE_FILE>` exists at `<REPO_ROOT>`, apply the same cross-check to any
`status:` fields found there.

---

## Step 5 — Report

Output two tables followed by a summary.

**Table 1: Suspicious `done` plans**

| Plan file       | Keywords searched | Last matching commit    | Verdict   |
| --------------- | ----------------- | ----------------------- | --------- |
| `plans/foo.md`  | `foo`, `bar`      | `abc1234 feat: add foo` | confirmed |
| `plans/baz.md`  | `baz`             | none found              | STALE?    |

**Table 2: Suspicious `open` plans**

| Plan file       | Keywords searched | Matching commits            | Verdict |
| --------------- | ----------------- | --------------------------- | ------- |
| `plans/qux.md`  | `qux`             | `def5678 feat: qux support` | LANDED? |

**Summary line:**

