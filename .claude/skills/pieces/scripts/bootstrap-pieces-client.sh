#!/usr/bin/env bash
# bootstrap-pieces-client.sh
# Joins any tailnet device to the Pieces knowledge mesh on mac-mini.
# Run once on any new device. Supports macOS and Linux (systemd).
#
# Usage: bash bootstrap-pieces-client.sh
# Requirements: Tailscale connected, SSH access to mac-mini already works

set -euo pipefail

RENTAMAC="mac-mini.taila01bd5.ts.net"
RENTAMAC_USER="rentamac"
RENTAMAC_PORT=39300
LOCAL_PORT=39300
KEY_FILE="$HOME/.ssh/pieces_tunnel_ed25519"
SERVICE_NAME="pieces-tunnel"

OS=$(uname -s)
HOSTNAME=$(hostname -s)

echo "==> Bootstrapping Pieces client on $HOSTNAME ($OS)"

# ── 1. Verify tailnet connectivity ──────────────────────────────────────────
echo "Checking rentamac reachability..."
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
         -o IdentityAgent=none -o IdentitiesOnly=yes \
         -i "$KEY_FILE" "$RENTAMAC_USER@$RENTAMAC" true 2>/dev/null; then
  echo "  → Key not yet authorized. Generating key and authorizing..."

  if [ ! -f "$KEY_FILE" ]; then
    ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -C "$HOSTNAME pieces tunnel"
    echo "  → Key generated: $KEY_FILE"
  fi

  echo "  → Add this public key to mac-mini's authorized_keys:"
  echo ""
  cat "${KEY_FILE}.pub"
  echo ""
  echo "  Run on mac-mini:"
  echo "    echo '$(cat ${KEY_FILE}.pub)' >> ~/.ssh/authorized_keys"
  echo ""
  read -rp "Press enter once the key is authorized on mac-mini..."
fi

# ── 2. Install uv if missing ─────────────────────────────────────────────────
if ! command -v uv &>/dev/null && [ ! -f "$HOME/.local/bin/uv" ]; then
  echo "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
UV="$HOME/.local/bin/uv"
[ ! -f "$UV" ] && UV=$(command -v uv)

# ── 3. Install pieces-cli ────────────────────────────────────────────────────
echo "Installing pieces-cli..."
"$UV" tool install pieces-cli 2>&1 | grep -E "Installed|already|error" || true
export PATH="$HOME/.local/bin:$PATH"

# ── 4. Set up persistent SSH tunnel ─────────────────────────────────────────
SSH_CMD="/usr/bin/ssh -N \
  -i ${KEY_FILE} \
  -o StrictHostKeyChecking=no \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  -o IdentitiesOnly=yes \
  -o IdentityAgent=none \
  -L ${LOCAL_PORT}:localhost:${RENTAMAC_PORT} \
  ${RENTAMAC_USER}@${RENTAMAC}"

if [ "$OS" = "Darwin" ]; then
  # ── macOS: LaunchAgent ───────────────────────────────────────────────────
  PLIST="$HOME/Library/LaunchAgents/com.pieces.tunnel.plist"
  cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.pieces.tunnel</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/ssh</string>
        <string>-N</string>
        <string>-i</string>
        <string>${KEY_FILE}</string>
        <string>-o</string><string>StrictHostKeyChecking=no</string>
        <string>-o</string><string>ServerAliveInterval=30</string>
        <string>-o</string><string>ServerAliveCountMax=3</string>
        <string>-o</string><string>ExitOnForwardFailure=yes</string>
        <string>-o</string><string>IdentitiesOnly=yes</string>
        <string>-o</string><string>IdentityAgent=none</string>
        <string>-L</string>
        <string>${LOCAL_PORT}:localhost:${RENTAMAC_PORT}</string>
        <string>${RENTAMAC_USER}@${RENTAMAC}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/pieces-tunnel.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/pieces-tunnel.err</string>
</dict>
</plist>
EOF
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST"
  echo "  → LaunchAgent loaded: com.pieces.tunnel"

else
  # ── Linux: systemd user service ──────────────────────────────────────────
  mkdir -p "$HOME/.config/systemd/user"
  SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"
  cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Pieces tunnel to mac-mini knowledge layer
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/ssh -N -i ${KEY_FILE} -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -o IdentitiesOnly=yes -o IdentityAgent=none -L ${LOCAL_PORT}:localhost:${RENTAMAC_PORT} ${RENTAMAC_USER}@${RENTAMAC}
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now "${SERVICE_NAME}.service"
  echo "  → systemd service enabled: ${SERVICE_NAME}"
fi

# ── 5. Verify ────────────────────────────────────────────────────────────────
echo "Waiting for tunnel..."
sleep 4
if curl -sf --max-time 3 "http://localhost:${LOCAL_PORT}/.well-known/health" > /dev/null; then
  echo ""
  echo "✓ Pieces knowledge mesh connected on $HOSTNAME"
  echo "  PiecesOS: http://localhost:${LOCAL_PORT}"
  echo "  CLI:      pieces ask 'what was I working on?'"
else
  echo "✗ Tunnel not yet responding — check: ssh -i $KEY_FILE $RENTAMAC_USER@$RENTAMAC"
fi
