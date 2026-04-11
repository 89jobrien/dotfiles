---
name: using-toolz
description: Use when doing system maintenance, analyzing logs, querying databases, or working with the local RAG store. toolz is a personal swiss-army CLI at ~/.local/bin/toolz.
---

# Using toolz

`toolz` is a personal CLI at `~/.local/bin/toolz` with four subcommands.

## sys — System maintenance

```bash
toolz sys --brew       # brew update + cleanup
toolz sys --docker     # docker image/container prune
toolz sys --git        # git gc on all ~/dev repos
toolz sys --cargo      # cargo sweep on ~/dev
toolz sys --cache      # clean npm/uv/system caches
toolz sys --dry-run    # preview without executing (combine with any flag)
```

Flags can be combined: `toolz sys --brew --docker --cache`

## log — Log analysis

```bash
toolz log analyze <file>   # summary stats for a log file
toolz log errors <file>    # extract error/warn lines
```

## ai — AI chat and RAG

```bash
toolz ai chat                          # interactive REPL chat
toolz ai chat --provider openai        # override provider (openai|gemini|ollama)
toolz ai chat --model <model>          # override model

toolz ai rag add <file>                # add file to RAG store
toolz ai rag query "<question>"        # query the RAG store
toolz ai rag status                    # show RAG store stats
```

## db — Database management

```bash
toolz db list                          # list configured connections
toolz db connect <name>                # open interactive shell
toolz db query <name> "<sql>"          # run a SQL query
toolz db add <name> <connection>       # add a named connection
toolz db backup <name>                 # backup a database
```
