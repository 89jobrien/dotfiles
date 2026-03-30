---
name: chunked-file-reading
description: Use when reading large files (logs, JSONL, CSVs) that exceed context limits, when the Read tool returns truncated output, or when needing to locate a specific section in a multi-thousand-line file without reading everything.
---

# Chunked File Reading

## Overview

The `Read` tool has no `head`/`tail` equivalent and will truncate large files. The escape hatch is `offset` + `limit` parameters. Grep keywords first to find approximate line numbers, then read only the relevant window.

## Pattern

```
1. Grep for a keyword to get line numbers
2. Read a window around the match (offset = line - buffer, limit = 50-100)
3. Navigate forward/backward by adjusting offset
```

## Step-by-Step

**Step 1 — find the needle:**
```
Grep: pattern="error|panic|FAILED", path="/path/to/file.log", output_mode="content", -n=true
→ Returns: "4821:  thread 'main' panicked at..."
```

**Step 2 — read the window:**
```
Read: file_path="/path/to/file.log", offset=4810, limit=40
```

**Step 3 — navigate if needed:**
- Earlier context: subtract from offset (`offset=4780`)
- Later output: add to offset (`offset=4850`)
- Didn't find it: try a different grep term

## JSONL Session Files

Each line is a self-contained JSON object. To find a specific message:

```bash
# Get line count first
wc -l /path/to/session.jsonl

# Grep for the content keyword — shows line number
Grep: pattern="the thing I'm looking for", path="session.jsonl", output_mode="content", -n=true

# Read 20 lines around the match
Read: offset=<line_number - 5>, limit=20
```

JSONL schema:
```json
{"type": "human|assistant|tool_result", "message": {...}, "timestamp": "..."}
```

For assistant messages with tool use, the tool call and its result appear as consecutive lines linked by `tool_use_id`.

## Large Binary Search (Unknown Location)

When you don't know where the content is and grep gives too many hits:

```
1. wc -l → N total lines
2. Read offset=N/2, limit=5 → check if before or after target
3. Halve the remaining range, repeat
4. Takes ~log2(N) reads — 4000-line file needs ≤12 reads
```

## Limits and Gotchas

| Issue | Fix |
|---|---|
| `offset` is 1-based (line 1 = `offset=1`) | Don't use `offset=0` |
| File truncated at 2000 lines by default | Always set explicit `limit` for large files |
| Grep returns too many matches | Add context: more specific pattern, or use `-C` for surrounding lines |
| JSONL lines are very long (truncated at 2000 chars) | Content is there — the JSON object continues; use grep on the specific field |
| Session files in multiple projects | Check `/Users/joe/.claude/projects/*/` — each subfolder is a project |
