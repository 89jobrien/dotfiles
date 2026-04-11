---
name: using-conductor
description: Use after a significant commit or when CI fails to run the devloop → doob → devkit workflow pipeline. Conductor creates doob tasks from findings and summarizes health. Invoke via /conduct or let forge dispatch it after commits.
---

# $using-conductor — Workflow Orchestrator

## Purpose

Conductor connects your tools into a cohesive pipeline. It runs devloop council analysis, creates doob tasks from findings, and handles CI failure triage. It does not fix code or make commits.

## When to Invoke

- After completing a significant feature or fix
- When CI fails and you want a diagnosis + task created
- When you want a branch health check with actionable output

## How to Invoke

```
/conduct                    ← standard loop on current branch
/conduct --ci <job-url>     ← CI failure mode with a job URL
```

## Standard Loop

1. Runs `devloop git` council analysis on current branch
2. Parses health score and findings from all council roles
3. Creates `doob` tasks:
   - Blocking findings → high priority
   - Suggestions → normal priority
   - Each task includes: what was flagged, which file/area, council role that flagged it
4. Optionally runs `devkit review` for a second-pass diff review (triggers when health score < 70)
5. Reports summary: health score, number of tasks created, anything needing immediate attention

## CI Failure Mode

1. Receives failed CI job URL or detects failure from devkit ci-agent
2. Diagnoses: parses logs, identifies failure type (compile error, test failure, lint, etc.)
3. Creates a `doob` task with: what failed, probable cause, relevant files, suggested fix direction
4. Links to current devloop health score

## Output Format

```
## Conductor Report

**Branch health:** 84/100
**Tasks created:** 3 (1 high priority, 2 normal)

### Created tasks
- [HIGH] #42 — Hexagonal boundary leak in container adapter (sentinel: blocking)
- [NORMAL] #43 — Missing error context in pull_image (analyst: suggestion)
- [NORMAL] #44 — No test for new overlay mount path (critic: suggestion)

### Immediate attention
None — no blocking CI failures.
```

Each step is logged so you can see exactly what was done and why each task was created.

## Dispatched by Forge

Forge dispatches conductor after significant commits or when you mention CI failures. Invoke directly via `/conduct` for explicit pipeline runs.
