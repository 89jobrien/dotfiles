# mcp-remote Stdio Bridge

Use when your MCP client only supports stdio transport (e.g., Claude Desktop, Zed, OpenClaw).
Bridges stdio clients to PiecesOS's HTTP/SSE endpoints.

## Install

```bash
# Pin to a specific version — avoid npx (security/performance)
npm install -g mcp-remote@0.1.38
```

**Requirements:** Node.js 18+, npm in PATH.

## Endpoint to Use

For stdio bridge clients, use the **SSE endpoint**:
```
http://localhost:39300/model_context_protocol/2024-11-05/sse
```

## Config by Client

### Claude Desktop
`~/Library/Application Support/Claude/claude_desktop_config.json` (macOS)
`%APPDATA%\Claude\claude_desktop_config.json` (Windows)

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

### Zed
`settings.json` — uses `context_servers`, not `mcpServers`:

```json
{
  "context_servers": {
    "pieces": {
      "command": {
        "path": "mcp-remote",
        "args": ["http://localhost:39300/model_context_protocol/2024-11-05/sse"],
        "env": {}
      },
      "settings": {}
    }
  }
}
```

## Flags

| Flag | Purpose |
|---|---|
| `--allow-http` | Allow HTTP URLs (trusted networks only) |
| `--debug` | Verbose logs → `~/.mcp-auth/{hash}_debug.log` |
| `--silent` | Suppress default logs |

## Verify

```bash
curl http://localhost:39300/.well-known/version
```

After configuring, restart your client and ask: *"What tools do you have from Pieces?"*
