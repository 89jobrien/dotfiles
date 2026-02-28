#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[personal-mcp] %s\n' "$*"
}

HOME_DIR="${HOME}"
CTX_DIR="${HOME_DIR}/.ctx"
HANDOFF_DIR="${CTX_DIR}/handoffs"
CHAT_DIR="${CTX_DIR}/chats"
MCP_CTX_DIR="${MCP_CTX_DIR:-${CTX_DIR}}"
MCP_BIN="${HOME_DIR}/.local/bin/personal-mcp"
MCP_REPO="${HOME_DIR}/dev/personal-mcp"

CLAUDE_CFG="${HOME_DIR}/Library/Application Support/Claude/claude_desktop_config.json"
CURSOR_CFG="${HOME_DIR}/.cursor/mcp.json"
ZED_CFG="${HOME_DIR}/.config/zed/settings.json"
CODEX_CFG="${HOME_DIR}/.codex/config.toml"
OPENCODE_CFG="${HOME_DIR}/.config/opencode/opencode.json"

ensure_dirs() {
  mkdir -p "${HANDOFF_DIR}" "${CHAT_DIR}" "$(dirname "${CLAUDE_CFG}")" "$(dirname "${CURSOR_CFG}")" "$(dirname "${ZED_CFG}")" "$(dirname "${OPENCODE_CFG}")" "$(dirname "${CODEX_CFG}")"
  log "ensured context dirs under ${CTX_DIR}"
}

install_binary() {
  if [[ ! -d "${MCP_REPO}" ]]; then
    log "repo not found at ${MCP_REPO}; skipping binary install."
    return 0
  fi
  log "installing personal-mcp to ~/.local/bin ..."
  if cargo install --path "${MCP_REPO}" --root "${HOME_DIR}/.local" --force; then
    log "installed ${MCP_BIN}"
    return 0
  fi

  if [[ -x "${MCP_BIN}" ]]; then
    log "cargo install failed; using existing binary at ${MCP_BIN}"
    return 0
  fi

  log "cargo install failed and no existing binary found at ${MCP_BIN}"
  return 1
}

install_opencode_if_missing() {
  if command -v opencode >/dev/null 2>&1; then
    log "opencode already installed: $(command -v opencode)"
    return 0
  fi
  if command -v brew >/dev/null 2>&1; then
    log "installing opencode via brew ..."
    brew install opencode || {
      log "failed to install opencode via brew; continuing."
      return 0
    }
    log "opencode installed: $(command -v opencode)"
    return 0
  fi
  log "opencode not found and brew unavailable; skipping."
}

merge_claude_config() {
  local tmp
  tmp="$(mktemp)"
  if [[ -f "${CLAUDE_CFG}" ]]; then
    cp "${CLAUDE_CFG}" "${tmp}"
  else
    printf '{}' > "${tmp}"
  fi

  jq \
    --arg cmd "${MCP_BIN}" \
    --arg mcp_ctx "${MCP_CTX_DIR}" \
    '
    .mcpServers = (.mcpServers // {}) |
    .mcpServers.personal = {
      "type": "stdio",
      "command": $cmd,
      "args": [],
      "env": { "MCP_CTX_DIR": $mcp_ctx }
    }
    ' "${tmp}" > "${tmp}.new"

  mv "${tmp}.new" "${CLAUDE_CFG}"
  rm -f "${tmp}"
  log "updated Claude Desktop MCP config: ${CLAUDE_CFG}"
}

merge_cursor_config() {
  local tmp
  tmp="$(mktemp)"
  if [[ -f "${CURSOR_CFG}" ]]; then
    cp "${CURSOR_CFG}" "${tmp}"
  else
    printf '{}' > "${tmp}"
  fi

  jq \
    --arg cmd "${MCP_BIN}" \
    --arg mcp_ctx "${MCP_CTX_DIR}" \
    '
    .mcpServers = (.mcpServers // {}) |
    .mcpServers.personal = {
      "command": $cmd,
      "args": [],
      "env": { "MCP_CTX_DIR": $mcp_ctx }
    }
    ' "${tmp}" > "${tmp}.new"

  mv "${tmp}.new" "${CURSOR_CFG}"
  rm -f "${tmp}"
  log "updated Cursor MCP config: ${CURSOR_CFG}"
}

merge_zed_config() {
  local tmp
  tmp="$(mktemp)"
  if [[ -f "${ZED_CFG}" ]]; then
    cp "${ZED_CFG}" "${tmp}"
  else
    printf '{}' > "${tmp}"
  fi

  jq \
    --arg cmd "${MCP_BIN}" \
    --arg mcp_ctx "${MCP_CTX_DIR}" \
    '
    .context_servers = (.context_servers // {}) |
    .context_servers.personal = {
      "command": $cmd,
      "args": [],
      "env": { "MCP_CTX_DIR": $mcp_ctx }
    }
    ' "${tmp}" > "${tmp}.new"

  mv "${tmp}.new" "${ZED_CFG}"
  rm -f "${tmp}"
  log "updated Zed MCP config: ${ZED_CFG}"
}

merge_opencode_config() {
  local tmp
  tmp="$(mktemp)"
  if [[ -f "${OPENCODE_CFG}" ]]; then
    cp "${OPENCODE_CFG}" "${tmp}"
  else
    printf '{}' > "${tmp}"
  fi

  jq \
    --arg cmd "${MCP_BIN}" \
    --arg mcp_ctx "${MCP_CTX_DIR}" \
    '
    ."$schema" = (."$schema" // "https://opencode.ai/config.json") |
    .mcp = (.mcp // {}) |
    .mcp.personal = {
      "type": "local",
      "command": [$cmd],
      "enabled": true,
      "environment": { "MCP_CTX_DIR": $mcp_ctx }
    }
    ' "${tmp}" > "${tmp}.new"

  mv "${tmp}.new" "${OPENCODE_CFG}"
  rm -f "${tmp}"
  log "updated OpenCode MCP config: ${OPENCODE_CFG}"
}

merge_codex_config() {
  touch "${CODEX_CFG}"

  if rg -n '^\[mcp_servers\.personal\]' "${CODEX_CFG}" >/dev/null 2>&1; then
    log "codex personal MCP block already present in ${CODEX_CFG}; leaving existing config."
    return 0
  fi

  cat >> "${CODEX_CFG}" <<EOF

[mcp_servers.personal]
command = "${MCP_BIN}"
args = []

[mcp_servers.personal.env]
MCP_CTX_DIR = "${MCP_CTX_DIR}"

EOF
  log "updated Codex MCP config: ${CODEX_CFG}"
}

main() {
  ensure_dirs
  install_binary
  install_opencode_if_missing
  command -v jq >/dev/null 2>&1 || { log "jq required"; exit 1; }
  merge_claude_config
  merge_cursor_config
  merge_zed_config
  merge_codex_config
  merge_opencode_config
  log "done. Restart Claude/Cursor/Zed/OpenCode/Codex to load updated MCP servers."
}

main "$@"
