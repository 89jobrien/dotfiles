#!/usr/bin/env bash
# setup-nushell.sh — nushell post-install configuration
# Creates a nu-login wrapper so terminals (Zed, etc.) can invoke nu as a login
# shell without hitting mise shim limitations.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="nushell"

WRAPPER="${HOME}/.local/bin/nu-login"
SHIM="${HOME}/.local/share/mise/shims/nu"

if ! has_cmd nu && [[ ! -f "$SHIM" ]]; then
    log_skip "nu not installed yet — skipping"
    exit 0
fi

NU_BIN="$SHIM"
if ! has_cmd nu && [[ ! -f "$SHIM" ]]; then
    NU_BIN="$(command -v nu 2>/dev/null || true)"
fi

mkdir -p "$(dirname "$WRAPPER")"

cat > "$WRAPPER" <<EOF
#!/bin/sh
# nu-login — login shell wrapper for nushell.
# Terminals invoke shells with a leading dash (e.g. "-nu"); mise shims
# don't handle that. This wrapper passes all args through to the real binary.
exec ${NU_BIN} "\$@"
EOF

chmod +x "$WRAPPER"
log_ok "nu-login wrapper → ${WRAPPER}"
