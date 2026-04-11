---
name: analyze
description: Deep codebase analysis — architecture health, test coverage gaps, tech debt, and actionable findings
trigger: /analyze
tags: [architecture, rust, analysis]
---

# Analyze Skill

Run a structured codebase analysis and produce actionable findings.

## Steps

1. **Orient** — read `CLAUDE.md`, `Cargo.toml` (workspace members), and recent `git log --oneline -20`.

2. **Spawn parallel sub-agents** for independent analysis streams:
   - **Architecture agent**: Check for hexagonal boundary violations (infra types leaking into domain, missing trait abstractions), SOLID principle adherence, module cohesion
   - **Test coverage agent**: Find untested public functions, missing edge cases, snapshot tests that need updating
   - **Tech debt agent**: Find TODOs/FIXMEs, dead code (`#[allow(dead_code)]`), large files (>500 lines), duplicated logic

3. **Quality gates** — run and report:
   - `cargo clippy --all-targets 2>&1 | grep -E "^error|^warning" | head -30`
   - `cargo test --quiet 2>&1 | tail -20`

4. **Synthesize findings** into a prioritized report:

   ```
   ## Critical (block next PR)
   - ...

   ## High (fix this sprint)
   - ...

   ## Low (backlog)
   - ...
   ```

5. Offer to create doob tasks from findings (`bd create`) if the user wants to track them.

## Rules

- Focus on actionable findings, not general observations.
- Cap output at ~40 findings total — prioritize ruthlessly.
- Do not make code changes. This skill is read-only.
