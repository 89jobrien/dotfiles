---
name: using-gkg
description: Use when needing a structured knowledge graph of a codebase for exploration or search. gkg indexes repositories and serves a queryable graph. Available at ~/.local/bin/gkg.
---

# Using gkg

`gkg` creates a structured, queryable knowledge graph of code repositories. Available at `~/.local/bin/gkg`.

## Indexing

```bash
gkg index                        # index repos in current directory
gkg index ~/dev                  # index all repos in ~/dev
gkg index --threads 4            # use specific thread count (default: auto)
gkg index --verbose              # verbose output
gkg index --stats                # print stats after indexing
gkg index --stats=stats.json     # save stats to file
```

## Server

```bash
gkg server start    # start the gkg server (makes graph queryable)
gkg server stop     # stop the running server
```

## Cleanup

```bash
gkg remove          # remove a workspace or project from the graph
gkg clean           # remove all indexed data
```

## When to use

- Use `gkg index` before deep codebase exploration tasks so the graph is fresh
- Use `gkg server start` when you need to query the graph interactively
- Prefer gkg over raw grep/glob for large workspace-wide searches across multiple repos
