---
name: pieces
description: |
  Use when working with Pieces — the on-device AI memory and productivity platform for developers.
  Covers: PiecesOS setup and architecture, Long-Term Memory (LTM) queries, MCP integration with
  Claude/Cursor/GitHub Copilot/VS Code/Zed/JetBrains and 15+ other clients, CLI usage (save/search
  snippets), Desktop App (Timeline, summaries, Copilot), IDE plugins (VS Code, JetBrains), and the
  Obsidian plugin. Trigger on: "pieces", "PiecesOS", "LTM", "Pieces MCP", "pieces copilot",
  "pieces drive", "pieces obsidian", "pieces timeline", or any task involving Pieces integrations.
---

## Core Architecture

Pieces is built on three interconnected pillars:

1. **LTM-2.7 (Long-Term Memory Engine)** — automatically captures your workflow (sites, tools, saved
   materials, conversations) every 20 minutes without requiring manual input. Stores up to 9 months
   of history. Powers everything else.
2. **Pieces Copilot** — AI chat with access to your LTM context and 40+ local/cloud LLMs. Available
   in Desktop App, IDE plugins, CLI, and Obsidian.
3. **Pieces Drive** — snippet management: save, enrich, search, and share code snippets across all
   Pieces surfaces. Automatically generates tags, titles, authorship, and descriptions via AI.

**Privacy:** Fully on-device by default. Air-gapped from cloud. Cloud LLMs are opt-in.

---

## PiecesOS — The Service Layer

The required background service (like a Docker daemon) that everything depends on.

- **Ports:** `localhost:39300–39399`
- **Health check:** `GET http://localhost:39300/.well-known/health` → returns a UUID
- **CORS:** `access-control-allow-origin: *`
- **Key endpoints:** `/.well-known/health`, `/user`, `/applications`
- **Platforms:** macOS (Intel + Apple Silicon), Windows 10/11, Linux (Ubuntu 22+)

PiecesOS **must be running** before CLI, MCP, IDE plugins, or Obsidian plugin will work.

**Settings available in Desktop App:** Account, LTM, Models, Copilot Chats, Machine Learning,
MCP, Connected Applications, Views & Layouts, Appearance, Troubleshooting.

---

## Desktop App

The central hub for the Pieces suite.

**Timeline**
- Horizontal view of your activity across 24 hours; hover for timestamps and memory counts
- Stores up to 9 months of captured context
- Browse by time range, then chat or generate summaries from any slice

**One-Click Summaries** — preset types:
- `What's Top of Mind` — current focus areas
- `Standup Update` — yesterday/today/blockers
- `Day Recap` — end-of-day overview
- `Custom Summary` — user-defined prompt
- `AI Habits` — patterns in your workflow

**Conversational Search** — chat interface for querying LTM. Suggested prompts appear on load.
Examples: "What was the link to that doc I worked on last week?" / "What did I decide about auth?"

---

## Pieces Copilot

AI assistant available across all Pieces surfaces.

- **Models:** 40+ cloud-hosted and local models (includes Ollama-served local models)
- **Context sources you can attach:**
  - LTM history (toggle on/off per conversation)
  - Local folders and files
  - Saved Pieces Drive snippets
  - Website URLs for reference
- **Quick Actions** — pre-built prompts for common tasks (explain, comment, debug, etc.)
- **Suggested Prompts** — shown at conversation start to help get oriented

Use local models for privacy/speed; cloud models for more capability. Switch per conversation.

---

## CLI

Install: `pip install pieces-cli` or `conda install pieces-cli`

```bash
pieces run              # Interactive loop mode (omit 'pieces' prefix for all commands inside)
pieces list             # List all Pieces Drive materials (alias: drive)
pieces list models      # Show available AI models
pieces create           # Save clipboard content as a snippet
pieces search "query"               # Fuzzy search
pieces search "query" --mode ncs    # Neural code search
pieces search "query" --mode fts    # Full text search
pieces edit             # Rename/reclassify a snippet
pieces delete           # Remove a snippet
pieces ask "question"   # Ask Pieces Copilot
pieces chats            # List past conversations
pieces commit           # Auto-generate git commit message (--push to push)
pieces share            # Generate shareable snippet URL
pieces mcp setup        # Configure Pieces MCP for a platform (interactive)
pieces version          # Show PiecesOS + CLI versions
pieces help             # List all commands
```

**Attach context to `ask`:**
- `-m 1 2` — attach saved materials by index
- `-f ./path` — attach file or folder

- Navigate search results with arrow keys; Enter to view snippet with full metadata
- Inside `pieces run`, omit the `pieces` prefix: just `create`, `search "query"`, etc.

---

## MCP Integration

Connects PiecesOS context into AI clients via the `ask_pieces_ltm` tool.

**Requirement:** PiecesOS running + Long-Term Memory enabled.

**`ask_pieces_ltm`** — the core MCP tool. Queries your captured LTM history. Use it to:
- Retrieve past debugging sessions, decisions, and code context
- Find implementations you worked on previously
- Answer "what was I doing last Thursday?" style queries

**Claude Code (fastest setup):**
```bash
pieces mcp setup   # interactive — select "Claude Code"
# or manually:
claude mcp add --transport http pieces http://localhost:39300/model_context_protocol/2025-03-26/mcp
```

**Stdio-only clients (Claude Desktop, Zed):** Use `mcp-remote` — see [references/mcp-remote.md](references/mcp-remote.md).

**Remote access:** Tailscale (point at `100.x.x.x:39300`) or ngrok (expose port 39300).

See [references/mcp-platforms.md](references/mcp-platforms.md) for all platform configs.
See [scripts/add-pieces-mcp.sh](scripts/add-pieces-mcp.sh) to automate Claude Code setup.

---

## IDE Plugins

### JetBrains (IntelliJ, WebStorm, PyCharm, CLion, etc.)
Minimum version: 2023.1. Install from [JetBrains Plugin Marketplace](https://plugins.jetbrains.com/plugin/17328-pieces).

Right-click menu actions:
| Action | What it does |
|---|---|
| `Save Current Selection/File to Pieces` | Save with AI-enriched metadata |
| `Ask Copilot About Selection` | Get suggestions or explanations |
| `Modify Selection with Copilot` | Refine selected code with AI |
| `Comment Selection with Copilot` | Auto-generate inline docs |
| `Explain Selection with Copilot` | LLM-powered explanation |
| `Share via Pieces Link` | Generate a shareable link |
| `Search Pieces Drive` | Find saved snippets |

**Inline Quick Actions:** `Pieces: Explain` and `Pieces: Comment` appear above functions automatically.
**Search shortcut:** Double-tap Shift → Pieces search window.

### VS Code
One-click MCP install available. Copilot and Drive features mirror JetBrains.

---

## Obsidian Plugin

Install from the Obsidian plugin marketplace.

- Save code snippets to Pieces Drive via right-click context menu
- AI auto-enriches with tags, titles, authorship, descriptions
- Pieces sidebar: search by keyword/tag, insert snippet at cursor
- Share snippets via generated links
- Run Pieces Copilot conversations with LTM context inside Obsidian

---

## Common Workflows

**Save a snippet from clipboard:**
```bash
pieces create
```

**Query past work context (via MCP in any connected AI client):**
```
ask_pieces_ltm: "What auth approach did I use last week?"
```

**Search for a saved snippet:**
```bash
pieces search "jwt middleware" --mode ncs
```

**Check if PiecesOS is alive:**
```bash
curl http://localhost:39300/.well-known/health
```

**Generate a standup update:** Desktop App → Timeline → select yesterday's range → "Standup Update"
