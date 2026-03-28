# Pieces MCP Platform Integrations

All platforms require PiecesOS running with Long-Term Memory enabled.

## MCP Endpoints

| Transport | URL |
|---|---|
| Streamable HTTP (recommended) | `http://localhost:39300/model_context_protocol/2025-03-26/mcp` |
| SSE (stdio bridge clients)    | `http://localhost:39300/model_context_protocol/2024-11-05/sse` |

Port may vary (39300–39399) — check PiecesOS Quick Menu or Desktop → Settings → MCP.

Verify PiecesOS is running:
```bash
curl http://localhost:39300/.well-known/version
```

---

## Claude Code (Recommended: auto-setup)

```bash
# Auto-setup via Pieces CLI
pieces mcp setup
# → select "Claude Code" from menu

# Or manually (HTTP transport, user-scoped)
claude mcp add --transport http pieces http://localhost:39300/model_context_protocol/2025-03-26/mcp

# SSE alternative
claude mcp add --transport sse pieces http://localhost:39300/model_context_protocol/2024-11-05/sse

# Project-scoped (writes .mcp.json at project root)
claude mcp add --transport http --scope project pieces http://localhost:39300/model_context_protocol/2025-03-26/mcp
```

Manage:
```bash
claude mcp list
claude mcp get pieces
claude mcp remove pieces
```

Config lives in `~/.claude.json` (user) or `.mcp.json` (project).

---

## Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS)
or `%APPDATA%\Claude\claude_desktop_config.json` (Windows):

```json
{
  "mcpServers": {
    "pieces": {
      "command": "mcp-remote",
      "args": ["http://localhost:39300/model_context_protocol/2024-11-05/sse"]
    }
  }
}
```

Requires `mcp-remote` — see [mcp-remote.md](mcp-remote.md).

---

## Quick-Install Platforms (One-Click in Pieces docs)
- **Cursor**
- **VS Code**

---

## Full Setup Required

| Platform | Notes |
|---|---|
| GitHub Copilot | Step-by-step in Pieces docs |
| Goose | Step-by-step in Pieces docs |
| Windsurf | Step-by-step in Pieces docs |
| Zed | Uses `context_servers` key — see [mcp-remote.md](mcp-remote.md) |
| JetBrains IDEs | Step-by-step in Pieces docs |
| Continue.dev | Step-by-step in Pieces docs |
| Cline | Step-by-step in Pieces docs |
| Raycast | Step-by-step in Pieces docs |
| Rovo Dev CLI | Step-by-step in Pieces docs |
| OpenAI Codex CLI | Step-by-step in Pieces docs |
| Google Gemini CLI | Step-by-step in Pieces docs |
| Amazon Q Developer | Step-by-step in Pieces docs |
| ChatGPT Developer Mode | Step-by-step in Pieces docs |

Full guides: https://docs.pieces.app/products/mcp/get-started

---

## Remote Access

**Target host:** A rentamac (always-on cloud Mac) is the preferred PiecesOS host for remote LTM access.

**Tailscale setup (production):**
PiecesOS binds to `localhost` only — must proxy to the Tailscale interface via socat.

```bash
# Install socat on the rentamac
brew install socat

# LaunchAgent: ~/Library/LaunchAgents/com.pieces.proxy.plist
# Proxies Tailscale IP:39301 → localhost:39300
# See scripts/pieces-proxy-launchagent.sh to generate it
```

Then on m5-max:
```bash
claude mcp add --transport http pieces "http://<tailscale-ip>:39301/model_context_protocol/2025-03-26/mcp"
```

**ngrok (alternative):** Expose port 39300, update MCP URL to the tunnel:
```bash
ngrok http 39300
```
