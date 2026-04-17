---
name: eod
description: >
  This skill should be used when the user runs "/eod", asks to "run end of day",
  "do the eod ritual", "wrap up the session", or "end of day". Executes a
  closing ritual: run parallel handoff across all active repos (24h git window),
  then update the Obsidian daily note.
argument-hint: "[optional notes to include in HANDOFF / daily note]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Agent
---

# End of Day Ritual

Two-phase closing ritual: parallel handoff across all active repos, then daily note update.

## Step 1 — Identify Active Repos

Active = any repo with commits in the past 24 hours. Check the allowlist only:

```bash
for repo in braid crux devkit devloop doob dotfiles harvestrs joe-dev joe-secrets kan maestro \
  magi mcpipe minibox notfiles obfsck personal-mcp pieces-ob rx slash steve; do
  git -C "$HOME/dev/$repo" log --since="24 hours ago" --oneline -1 2>/dev/null | \
    grep -q . && echo "$repo"
done
```

## Step 2 — Run Parallel Handoff

Dispatch one `atelier:minion` subagent per active repo, all in parallel (cap at 5 concurrent).

Each subagent runs the full `atelier:handoff` workflow:
1. `git branch --show-current && git log --oneline -5`
2. `handoff-detect` to find HANDOFF.yaml path
3. Read existing HANDOFF.yaml
4. `cargo check` / `cargo test` (or language equivalent) — capture build/test state
5. Update HANDOFF.yaml: prepend new log entry, remove completed items, keep open items
6. Write HANDOFF.yaml
7. Write `.ctx/HANDOFF.*.state.yaml`
8. `handoff-db upsert --project <project> --handoff <path>`
9. `handoff-reconcile sync --project <project> --handoff <path>`
10. Generate `.ctx/HANDOFF.md`
11. Ensure `.gitignore` covers `.ctx/`
12. `git add <handoff-path> .gitignore && git commit -m "docs: update handoff"`

Provide each subagent with a session summary (today's commits grouped by repo) so log entries
are narrative, not just commit lists.

Wait for all agents to complete. Collect results — note any flags (failing tests, uncommitted
changes, blocked items).

## Step 3 — Update Daily Note

Run the `daily-update` skill workflow:
- Get 24h git log across all active repos
- Find or create today's note at `$HOME/Documents/Obsidian Vault/01_Daily/YYYY-MM-DD.md`
- Append a new `---`-separated block — never overwrite existing blocks
- Append a handoff summary table at the bottom with one row per repo:
  `| Repo | Status | Next |`
- Update `# Links` section with all active repo names as `[[repo]]` links

## Step 4 — Report

Print a concise summary:

```
EOD ritual complete.
  Active repos  — <list>
  Handoffs      — <N> committed, <M> flags
  Daily note    — ~/Documents/Obsidian Vault/01_Daily/YYYY-MM-DD.md
  Flags         — <repo>: <issue> (or "none")
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Running handoff sequentially | Always parallel — one subagent per repo |
| Overwriting existing daily note blocks | Append only — existing blocks are immutable |
| Skipping repos with no new commits | Only process repos active in the past 24h |
| Committing `.ctx/HANDOFF.*.state.yaml` | State files are gitignored — never stage them |
| Using `--no-verify` | Never — let hooks run, fix failures |
