#!/usr/bin/env bash
# add-pieces-mcp.sh
# Adds Pieces MCP server to Claude Code (user-scoped, HTTP transport)
# Requires: PiecesOS running with LTM enabled
# Usage: bash add-pieces-mcp.sh [--project]

set -euo pipefail

SCOPE_FLAG=""
if [[ "${1:-}" == "--project" ]]; then
  SCOPE_FLAG="--scope project"
  echo "→ Using project scope (writes .mcp.json)"
else
  echo "→ Using user scope (~/.claude.json)"
fi

# Verify PiecesOS is reachable
echo "Checking PiecesOS..."
if ! curl -sf http://localhost:39300/.well-known/health > /dev/null; then
  echo "✗ PiecesOS not reachable at localhost:39300"
  echo "  Start it, then re-run this script."
  exit 1
fi
echo "✓ PiecesOS is running"

# Add MCP server
claude mcp add --transport http $SCOPE_FLAG pieces \
  "http://localhost:39300/model_context_protocol/2025-03-26/mcp"

echo "✓ Pieces MCP added"
echo ""
echo "Verify with:"
echo "  claude mcp list"
echo "  claude mcp get pieces"
