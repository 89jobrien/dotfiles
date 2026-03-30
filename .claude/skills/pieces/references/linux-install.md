# PiecesOS Linux Installation

## Requirements

- **OS:** Ubuntu 22+ (Ubuntu-based distros only)
- **RAM:** 8GB minimum (1GB free for cloud mode, 2GB free for local/on-device mode)
- **Storage:** 6GB minimum, 10GB+ recommended (4GB free for data)
- **CPU:** Any modern processor (multi-core preferred)
- **snapd** installed and enabled (included by default on recent Ubuntu)
- `sudo` access

## Install

```bash
# Install PiecesOS via snap
sudo snap install pieces-os

# Enable on-device ML/LLM features
sudo snap connect pieces-os:process-control :process-control

# Start PiecesOS
pieces-os
```

## Uninstall

```bash
sudo snap remove pieces-os
```

## Health Check

```bash
curl http://localhost:39300/.well-known/health
# Returns: ok:<UUID>

curl http://localhost:39300/.well-known/version
```

## Enable LTM (required for MCP)

After starting PiecesOS, enable Long-Term Memory via the PiecesOS Quick Menu or Desktop App → Settings → LTM before connecting any MCP clients.

## Headless / VPS Notes

- PiecesOS can run headless on Linux — no Desktop App required for MCP use
- The Desktop App is optional on Linux; PiecesOS alone exposes the MCP endpoints
- For remote access from other machines, expose port 39300 via Tailscale or ngrok
