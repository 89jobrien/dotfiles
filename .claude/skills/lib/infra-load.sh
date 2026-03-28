#!/usr/bin/env bash
# infra-load.sh — source this to get INFRA_* vars from ~/.claude/infra.toml
#
# Usage:
#   source "$(dirname "$0")/../lib/infra-load.sh"
#   ssh "$INFRA_DEV_USER@$INFRA_VPS_IP"

INFRA_TOML="${HOME}/.claude/infra.toml"

if [[ ! -f "$INFRA_TOML" ]]; then
    echo "error: ~/.claude/infra.toml not found — copy infra.toml.example and fill in values" >&2
    exit 1
fi

_infra_exports=$(uv run --script - "$INFRA_TOML" <<'PYEOF'
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
import sys, tomllib

path = sys.argv[1]
with open(path, "rb") as f:
    cfg = tomllib.load(f)

m = cfg.get("machines", {})
ts = cfg.get("tailscale", {})
op = cfg.get("onepassword", {})

pairs = {
    "INFRA_VPS_HOST":        m.get("vps", {}).get("host", ""),
    "INFRA_VPS_IP":          m.get("vps", {}).get("ip", ""),
    "INFRA_VPS_USER":        m.get("vps", {}).get("user", ""),
    "INFRA_VPS_OP_ITEM":     m.get("vps", {}).get("op_item", ""),
    "INFRA_VPS_OP_ACCOUNT":  m.get("vps", {}).get("op_account", ""),
    "INFRA_DEV_HOST":        m.get("dev", {}).get("host", ""),
    "INFRA_DEV_IP":          m.get("dev", {}).get("ip", ""),
    "INFRA_DEV_USER":        m.get("dev", {}).get("user", ""),
    "INFRA_LAB_HOST":        m.get("lab", {}).get("host", ""),
    "INFRA_MAC_MINI_HOST":   m.get("mac_mini", {}).get("host", ""),
    "INFRA_MAC_MINI_USER":   m.get("mac_mini", {}).get("user", ""),
    "INFRA_MAC_MINI_ADDR":   m.get("mac_mini", {}).get("tailscale_addr", ""),
    "INFRA_TAILSCALE_SUFFIX": ts.get("suffix", ""),
    "INFRA_OP_PERSONAL":     op.get("personal_account", ""),
}

for k, v in pairs.items():
    print(f'export {k}="{v}"')
PYEOF
)

eval "$_infra_exports"
unset _infra_exports
