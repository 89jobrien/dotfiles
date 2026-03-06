#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="nvim"

NVIM_DIR="${HOME}/.config/nvim"
NVIM_BAK_DIR="${HOME}/.config/nvim.backup.$(date +%Y%m%d-%H%M%S)"
AVANTE_FILE="${NVIM_DIR}/lua/plugins/avante.lua"

if ! has_cmd nvim; then
  log_skip "neovim not found"
  exit 0
fi

if [[ -d "${NVIM_DIR}" ]]; then
  if [[ ! -d "${NVIM_DIR}/.git" ]]; then
    log_warn "existing nvim config is not a git checkout; backing up to ${NVIM_BAK_DIR}"
    mv "${NVIM_DIR}" "${NVIM_BAK_DIR}"
  fi
fi

if [[ ! -d "${NVIM_DIR}" ]]; then
  log "cloning NvChad starter..."
  git clone https://github.com/NvChad/starter "${NVIM_DIR}"
fi

mkdir -p "$(dirname "${AVANTE_FILE}")"
cat >"${NVIM_DIR}/lua/chadrc.lua" <<'EOF'
---@type ChadrcConfig
local M = {}

M.base46 = {
  theme = "catppuccin",
}

return M
EOF

cat >"${AVANTE_FILE}" <<'EOF'
return {
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    version = false,
    build = "make",
    opts = {
      provider = "openai",
      auto_suggestions_provider = "openai",
    },
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "hrsh7th/nvim-cmp",
      "nvim-tree/nvim-web-devicons",
      {
        "MeanderingProgrammer/render-markdown.nvim",
        ft = { "markdown", "Avante" },
      },
    },
  },
}
EOF

# Count plugins from lazy-lock.json (approximate)
local plugin_count=0
if [[ -f "${NVIM_DIR}/lazy-lock.json" ]]; then
  plugin_count="$(grep -c '"' "${NVIM_DIR}/lazy-lock.json" 2>/dev/null || echo 0)"
fi

if [[ "${plugin_count}" -gt 0 ]]; then
  spin_silent "Syncing plugins ($plugin_count)..." nvim --headless "+Lazy! sync" +qa || true
else
  spin_silent "Syncing plugins..." nvim --headless "+Lazy! sync" +qa || true
fi

log_ok "NvChad + avante setup complete"
log "set your LLM provider API key before using Avante"
