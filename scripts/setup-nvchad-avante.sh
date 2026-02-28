#!/usr/bin/env bash
set -euo pipefail

NVIM_DIR="${HOME}/.config/nvim"
NVIM_BAK_DIR="${HOME}/.config/nvim.backup.$(date +%Y%m%d-%H%M%S)"
AVANTE_FILE="${NVIM_DIR}/lua/plugins/avante.lua"

log() {
  printf '[nvim-setup] %s\n' "$*"
}

if ! command -v nvim >/dev/null 2>&1; then
  log "Neovim not found. Install neovim first."
  exit 0
fi

if [[ -d "${NVIM_DIR}" ]]; then
  if [[ ! -d "${NVIM_DIR}/.git" ]]; then
    log "Existing nvim config is not a git checkout; backing it up to ${NVIM_BAK_DIR}"
    mv "${NVIM_DIR}" "${NVIM_BAK_DIR}"
  fi
fi

if [[ ! -d "${NVIM_DIR}" ]]; then
  log "Cloning NvChad starter..."
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

log "Syncing plugins via Lazy..."
nvim --headless "+Lazy! sync" +qa || true

log "NvChad + avante setup complete."
log "Set OPENAI_API_KEY (or configure another provider) before using Avante."
