---
name: devloop-analyze
description: Use when running devloop council analysis on a repo. Covers the correct op run invocation, model selection, and narrative output format. Invoke instead of `just analyze` which is broken.
---

# devloop-analyze

## The Problem with `just analyze`

The `just analyze` recipe is broken because it doesn't handle env conflicts from shell-injected `op://` vars.

## Correct Invocation

```bash
# The op-conflict-resolver hook will auto-detect conflicts and suggest the prefix.
# Manual form if needed:
env -u TAVILY_API_KEY -u CONTEXT7_API_KEY -u GEMINI_API_KEY -u FIRECRAWL_API_KEY \
  op run --account=my.1password.com --env-file=/Users/joe/.secrets -- \
  devloop analyze --repo /path/to/repo
```

Note: If op-conflict-resolver hook is active, just run `op run --account=my.1password.com --env-file=/Users/joe/.secrets -- devloop analyze --repo /path/to/repo` and the hook will correct it automatically.

## Model Selection

- **Use**: OpenAI models (gpt-4o, gpt-4o-mini)
- **Avoid**: Local qwen3 — returns 404, unreliable
- If devloop has a `--model` flag, specify explicitly

## Output Format Preference

When presenting council results:
- **Format**: Narrative timeline — one prose paragraph per time block (e.g., "Morning session", "Afternoon")
- **NOT**: Bullet point lists of commits
- **Tone**: Conversational, compact — describe what happened and why, not just what changed
- **Example**: "Tuesday morning was focused on stabilizing the BAML codegen pipeline — three commits in quick succession fixed the version mismatch between Cargo.toml and generators.baml that had been blocking the type-safe client generation."

## Pieces LTM Context

Before or after devloop analyze, query Pieces for historical context:
```
ask_pieces_ltm: "what was I working on in [repo name] recently?"
ask_pieces_ltm: "what problems did I hit with [specific feature]?"
```
Requires PiecesOS running: `curl -s http://localhost:39300/.well-known/health`

## Devloop Export

After analyze, export for sharing:
```bash
devloop export --repo /path/to/repo --output /tmp/report.md
```

## Common Failures

| Symptom | Fix |
|---------|-----|
| `op run` resolves wrong secret | Shell has conflicting var — use env -u or let hook auto-fix |
| Council returns no results | Check --repo path is correct git repo |
| qwen3 model errors | Switch to OpenAI model explicitly |
| PiecesOS not responding | `curl http://localhost:39300/.well-known/health` — restart if down |
