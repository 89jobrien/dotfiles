Render the /insights JSON output into a styled HTML report and a markdown report,
enriched with vector log telemetry.

## Step 1: Extract insights JSON

The user just ran /insights. The full insights JSON blob is in this conversation.
Extract the complete JSON object (everything between the outermost `{` and `}`).
Include all fields: project_areas, interaction_style, what_works, friction_analysis,
suggestions, on_the_horizon, fun_ending, at_a_glance.

Add two extra fields before saving:
- `_subtitle`: "N sessions total - M analyzed - X messages - Yh - Z commits - date range"
  (extract from the insights header)
- `_stats`: array of `{"value": "...", "label": "..."}` for: Messages, Compute, Commits,
  Sessions Analyzed, Goal Achievement, Sessions/Day

Save to `/tmp/insights-YYYYMMDD.json` (today's date).

## Step 2: Reframe with context

Before rendering, rewrite the insights JSON to add proper framing:

### Friction rates
Compute total tool calls from the vector log telemetry (Step 3 runs first if needed,
or estimate from the tool usage table in the insights). Then for each friction category
in `friction_analysis.categories`, prepend the count and rate to the description:
"N events out of T tool calls (X%). ..." Replace language like "frequently",
"often", "high friction" with the actual percentages.

Rewrite `friction_analysis.intro` to lead with the total friction rate:
"N total friction events across T tool calls (X% rate). These are course-corrections
within a Y%+ success pipeline, not systemic failures."

### Already-implemented annotations
Check every item in `suggestions.claude_md_additions`, `suggestions.features_to_try`,
`suggestions.usage_patterns`, and `on_the_horizon.opportunities` against the user's
actual setup:
- CLAUDE.md files (global `~/.claude/CLAUDE.md`, workspace `~/dev/CLAUDE.md`,
  per-project)
- Active hooks listed in CLAUDE.md (`~/.claude/hooks/nu/`)
- Custom skills (available skill list in this session)
- Plugins (atelier, sanctum, orca-strait, godmode)

For any item that's already implemented, add an `"_implemented"` field with a short
description of what exists. Use "Partially: ..." if only partly covered. The template
JS will render these as green badges.

### At a Glance reframe
Rewrite `at_a_glance.whats_hindering` to lead with friction rates and frame the gap
as "guardrails exist but aren't always followed" rather than "you need guardrails."
Rewrite `at_a_glance.quick_wins` to acknowledge what's already built and focus on
the remaining gap. Rewrite `at_a_glance.ambitious_workflows` to acknowledge existing
skill/tool implementations and focus on chaining them together.

### Interaction style reframe
In `interaction_style.narrative`, replace raw friction counts (e.g., "247 instances")
with rates against total tool calls (e.g., "247 times out of 57,760 tool calls (0.4%)").
Remove "despite the high friction counts" framing -- the counts aren't high relative
to the denominator.

## Step 3: Analyze vector logs

Run a python3 heredoc script against `~/logs/ai/vector/` JSONL files covering the
insights date range (files are `YYYY-MM-DD.jsonl` or `.jsonl.gz`). Aggregate:

- **Token economy**: total tokens, output tokens, cache creation tokens
  (`message.usage.cache_creation.ephemeral_1h_input_tokens` +
  `ephemeral_5m_input_tokens`; fall back to `cache_creation_input_tokens`),
  cache read tokens (`cache_read_input_tokens`), fresh input tokens (`input_tokens`),
  cache hit rate = `cache_read / (cache_read + cache_create + input) * 100`
- **Model split**: count `message.model` on `type: "assistant"` events, compute %
- **Project heatmap**: count events per project (last path component of `cwd` when
  under `/dev/`), top 10-15 by volume with %
- **Tool usage**: count `tool_use` blocks in assistant `message.content` arrays, top 10
  with % — **also output the total tool call count for friction rate calculations**
- **Permission modes**: count `permissionMode` values
- **Branch activity**: count `gitBranch` values, top 8
- **Hourly distribution**: bucket all events by hour from `timestamp`, note peak/low
  in local time (UTC-5)

Print structured results to stdout.

## Step 4: Render base HTML

Run: `nu ~/.claude/usage-data/render-insights.nu /tmp/insights-YYYYMMDD.json`

This injects the JSON into the template at `~/.claude/usage-data/template.html` and
writes `~/.claude/usage-data/report-YYYYMMDD.html`. The template already has a
`<div id="telemetry">` placeholder and all telemetry CSS classes.

## Step 5: Enrich HTML report

Edit the rendered `report-YYYYMMDD.html` to populate the telemetry section. Insert
content inside `<div class="telemetry-section" id="telemetry">`. Use these CSS classes
already in the template:
- `.telemetry-grid` (2-col grid), `.telemetry-card` for cards
- `.tbl` / `.tbl td.num` for data tables
- `.bar-row` / `.bar-track` / `.bar-fill` for horizontal bars (model split)
- `.cache-badge` for the cache hit rate callout
- `.hour-chart` / `.hour-bar` / `.hour-labels` for the 24-hour activity chart

Update the `#telemetry-intro` text with the actual date range and session count.

Add GitHub links to diagram nodes and architecture boxes. Use
`https://github.com/89jobrien/<repo>` for repo roots. For paths within repos:
- Directories: `<repo>/tree/main/<path>` (e.g., `atelier/tree/main/skills/cargo-gate`)
- Files: `<repo>/blob/main/<path>` (e.g., `atelier/blob/main/agents/maxion.md`)

Never use bare `<repo>/<path>` — GitHub returns 404 without `tree/main/` or `blob/main/`.
Skip links for repos that are private or disabled.

## Step 6: Generate markdown report

Write `~/.claude/usage-data/report-YYYYMMDD.md` with this structure:

```
# Claude Code Insights

{subtitle line}

## At a Glance

**What's working:** {whats_working}

**What's hindering:** {whats_hindering — reframed with friction rates}

**Quick wins:** {quick_wins — acknowledging what's already built}

**Ambitious workflows:** {ambitious_workflows — acknowledging existing tools}

---

| Stat | Value |
|------|-------|
{one row per _stats entry}

## Vector Log Enrichment ({date range})

{token economy table}
{model split table}
{project heatmap table}
{tool usage table}
{permission modes table}
{branch activity table}
{work schedule summary}

## What You Work On

### {area.name} ({area.session_count} sessions)

{area.description}

## How You Use Claude Code

{interaction_style.narrative — with friction rates not raw counts}

> **Key pattern:** {interaction_style.key_pattern}

## Impressive Things You Did

{what_works.intro}

### {workflow.title}

{workflow.description}

## Where Things Go Wrong

{friction_analysis.intro — with total rate}

### {category.category} ({count} instances)

{category.description — with rate against tool calls}

- {example 1}
- {example 2}

## Suggested CLAUDE.md Additions

### {n}. {addition} {-- ALREADY IMPLEMENTED if _implemented}

{*_implemented note in italics if present*}

> {why}

## Features to Try

### {feature.feature} {-- ALREADY IMPLEMENTED if _implemented}

{*_implemented note in italics if present*}

*{feature.one_liner}*

{feature.why_for_you}

```
{feature.example_code}
```

## Usage Patterns to Adopt

### {pattern.title} {-- ALREADY IMPLEMENTED if _implemented}

{*_implemented note in italics if present*}

{pattern.suggestion}

{pattern.detail}

```
{pattern.copyable_prompt}
```

## On the Horizon

{on_the_horizon.intro}

### {opportunity.title} {-- ALREADY/PARTIALLY IMPLEMENTED if _implemented}

{*_implemented note in italics if present*}

{opportunity.whats_possible}

```
{opportunity.copyable_prompt}
```

---

**Session of the Month:** {fun_ending.headline}. {fun_ending.detail}
```

## Step 7: Report

Print both output file paths:
- HTML: `file://~/.claude/usage-data/report-YYYYMMDD.html`
- Markdown: `~/.claude/usage-data/report-YYYYMMDD.md`
