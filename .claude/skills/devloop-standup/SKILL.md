---
name: devloop-standup
description: Use when asked to summarize recent repo activity, show what happened, or give a timeline view of work — with or without a time window argument
---

# Devloop Standup

Runs devloop council analysis + git log to produce a narrative timeline of recent repo activity.

## When to Use

- User asks "what happened?", "show me the timeline", "what did we do today?"
- User invokes this skill directly (e.g. `/devloop-standup` or `/devloop-standup 48h`)
- Default window: **24 hours**

## Argument Parsing

The skill accepts an optional time argument: `1h`, `6h`, `24h`, `48h`, `7d`, etc.

Parse from the invocation args. If absent, use `24h`. Convert to git `--since` value:
- `24h` → `--since="24 hours ago"`
- `7d` → `--since="7 days ago"`
- `2h` → `--since="2 hours ago"`

## Steps

### 1. Get commits in window

```bash
git log --format="%ad %s" --date=format:"%H:%M" --since="24 hours ago"
```

Group by rough time-of-day block: Early morning (00–06), Morning (06–12), Afternoon (12–17), Evening (17–21), Late evening (21–24).

### 1b. (Optional) Refresh gkg index

If the standup covers structural changes (new crates, major refactors), freshen the knowledge graph first:

```bash
gkg index /path/to/repo
```

### 2. Run devloop council analysis

```bash
export OPENAI_API_KEY=$(grep ^OPENAI_API_KEY ~/.secrets | cut -d= -f2)
~/.local/bin/devloop analyze --council --council-mode extensive --repo /path/to/repo
```

Use the council's summary, patterns, and recommendations as the analytical backbone. If the council flags specific work as a "saga" or investigation, name it.

### 3. Synthesize narrative output

Write in this style — **narrative, not structured report**:

```
Single branch (main), N commits, X sessions.

All work on YYYY-MM-DD:

- **Morning (HH:MM–HH:MM):** [what happened, what was built/fixed, what was the arc]
- **Afternoon (HH:MM–HH:MM):** [...]
- **Evening (HH:MM–HH:MM):** [...]
- **Late evening (HH:MM–HH:MM):** [name the saga if there was one — e.g. "cgroup debugging saga"]

[1-sentence close: what the session ended with / the outcome]
```

**Rules:**
- Time blocks only if there's activity in them (skip empty blocks)
- Name recurring themes or sagas (don't just list commits)
- End with the resolution or current state
- Keep it to ~10 lines total — dense > verbose
- If multiple days: group by day first, then time blocks within

## Writing to Daily Note

To record the standup in the Obsidian vault, use `devloop-daily-update` skill after synthesis.

## OPENAI_API_KEY Note

`source ~/.secrets` doesn't export — use the explicit export form above.

## Example Output

> Single branch (main), 52 commits, 3 sessions.
>
> All work on 2026-03-16:
>
> - **Early morning (00:54–07:48):** Hexagonal architecture refactor in 5 phases — domain traits, adapters, DI in handlers, mock tests, conformance suite. Cross-platform adapters for Windows/macOS/GKE added.
> - **Afternoon (13:46–16:57):** GKE unprivileged adapter suite, Zombienet pattern analysis, RuntimeCapabilities trait, state persistence across daemon restarts.
> - **Evening (16:35–18:57):** Ops runtime — VPS setup, systemd unit, install script, Justfile. Cgroup debugging began: controllers not delegating.
> - **Late evening (21:31–23:01):** Cgroup delegation saga — chased DelegateSubgroup=yes/supervisor confusion, diagnosed no-internal-processes constraint, fixed with supervisor leaf cgroup pattern. Confirmed `minibox run alpine -- /bin/true` working.
>
> Session closed clean: all commits pushed, cgroup fix verified on VPS.
