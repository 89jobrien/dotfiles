---
name: using-sentinel
description: Use when you need structured code review against hexagonal architecture, Rust conventions, or Go patterns. Invoke after implementing a feature, before opening a PR, or when reviewing a diff. Two modes: /watch for ongoing monitoring, /inspect for targeted one-shot review.
---

# $using-sentinel — Code Reviewer

## Purpose

Sentinel reviews code against your specific conventions and architecture patterns. It does not fix code — it flags and explains. You decide what to act on.

**Projects covered:** minibox (Rust), devloop (Rust), doob (Rust), devkit (Go)

## When to Invoke

- After implementing a feature or fix
- Before opening a PR
- When you want a second opinion on a diff
- When a CI failure smells like an architecture issue

## Modes

### `/inspect` — Targeted one-shot review

Reviews the current `git diff`, a specific file, or a set of files. Outputs a structured report and exits.

```
/inspect
/inspect src/domain/container.rs
/inspect -- HEAD~1
```

### `/watch` — Ongoing monitoring

Stays active and reviews each new diff as you work. Re-runs when you signal a new change is ready.

```
/watch
```

## What Sentinel Reviews

In priority order:

1. **Hexagonal arch boundaries** — domain logic leaking into adapters or vice versa
2. **Rust** — clippy issues, unsafe blocks, error handling patterns, async hygiene, missing `?` propagation
3. **Go (devkit)** — interface discipline, error wrapping with `%w`, goroutine leaks, context propagation
4. **Test coverage** — changed paths missing tests

## Output Format

```
## Sentinel Review

### Blocking
- [file:line] Issue description — why it matters

### Suggestions
- [file:line] Suggestion — rationale

### Observations
- [file:line] Note — no action needed
```

Blocking items must be resolved before merging. Suggestions are worth considering. Observations are FYI only.

## Dispatched by Forge

Forge dispatches sentinel automatically when you hand it a diff or ask for a review. You do not need to invoke sentinel directly unless you want a specific mode.
