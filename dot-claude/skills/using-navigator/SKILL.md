---
name: using-navigator
description: Use when jumping into a repo cold, starting a new dev session, or asking architecture questions about minibox, devloop, doob, or devkit. Produces a concise mental model briefing. Invoke via /navigate [repo] or let forge dispatch it automatically.
---

# $using-navigator — Context & Onboarding

## Purpose

Navigator primes your mental model for a repo. It reads structure, recent activity, and architecture docs, then gives you a briefing you can absorb in under 2 minutes. It does not make changes.

**Projects covered:** minibox, devloop, doob, devkit

## When to Invoke

- Jumping into a repo you haven't touched in a while
- Starting a new Claude Code session on a project
- Asking "how does X work?" about a repo's architecture
- Before writing a feature so you understand the lay of the land

## How to Invoke

```
/navigate minibox
/navigate devloop
/navigate doob
/navigate devkit
/navigate          ← infers from cwd
```

## What Navigator Produces

A structured briefing covering:

1. **What it does** — one paragraph, plain language
2. **Structure** — key crates/packages and what each owns
3. **Architecture pattern** — hexagonal layout, domain boundaries, key interfaces
4. **What's in flight** — recent branch activity, open work from devloop
5. **Gotchas** — known sharp edges, non-obvious constraints

Readable in under 2 minutes. No document dumps.

## Follow-up Q&A

After the initial briefing, navigator stays available in the session for architecture questions. It does not re-prime — it uses the context already loaded.

## How It Works Internally

1. Detects repo from argument or cwd
2. In parallel: runs `gkg` for structure, `devloop git` for branch health, reads CLAUDE.md + README + key arch files
3. Synthesizes into the briefing format above

## Dispatched by Forge

Forge dispatches navigator automatically when you ask architecture questions or jump into a cold repo context. Invoke directly via `/navigate` when you want to explicitly prime before starting work.
