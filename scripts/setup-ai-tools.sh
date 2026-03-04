#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
TAG="ai-tools"

HOME_DIR="${HOME}"
CTX_DIR="${HOME_DIR}/.ctx"
HANDOFF_DIR="${CTX_DIR}/handoffs"
CHAT_DIR="${CTX_DIR}/chats"
MCP_CTX_DIR="${MCP_CTX_DIR:-${CTX_DIR}}"
MCP_ENV_FILE_PATH="${MCP_ENV_FILE:-${HOME_DIR}/.config/dev-bootstrap/secrets.env}"
BAML_LOG_DEFAULT="${DOT_BAML_LOG_DEFAULT:-info}"
BOUNDARY_MAX_LOG_CHUNK_CHARS_DEFAULT="${DOT_BOUNDARY_MAX_LOG_CHUNK_CHARS_DEFAULT:-3000}"
MCP_BIN="${HOME_DIR}/.local/bin/personal-mcp"
MCP_REPO="${HOME_DIR}/dev/personal-mcp"

# Config file paths
CLAUDE_DESKTOP_CFG="${HOME_DIR}/Library/Application Support/Claude/claude_desktop_config.json"
CLAUDE_CODE_CFG="${HOME_DIR}/.claude/settings.json"
CURSOR_CFG="${HOME_DIR}/.cursor/mcp.json"
ZED_CFG="${HOME_DIR}/.config/zed/settings.json"
CODEX_CFG="${HOME_DIR}/.codex/config.toml"
OPENCODE_CFG="${HOME_DIR}/.config/opencode/opencode.json"
GEMINI_CFG="${HOME_DIR}/.gemini/settings.json"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

ensure_dirs() {
  mkdir -p "${HANDOFF_DIR}" "${CHAT_DIR}" \
    "$(dirname "${CLAUDE_DESKTOP_CFG}")" \
    "$(dirname "${CLAUDE_CODE_CFG}")" \
    "$(dirname "${CURSOR_CFG}")" \
    "$(dirname "${ZED_CFG}")" \
    "$(dirname "${OPENCODE_CFG}")" \
    "$(dirname "${CODEX_CFG}")" \
    "$(dirname "${GEMINI_CFG}")"
  log "ensured context dirs under ${CTX_DIR}"
}

# merge_json_config FILE JQ_FILTER [jq_args...]
#   Read FILE (or start from {}), apply JQ_FILTER, write back.
merge_json_config() {
  local cfg="$1" filter="$2"
  shift 2
  local tmp
  tmp="$(mktemp)"
  if [[ -f "${cfg}" ]]; then
    cp "${cfg}" "${tmp}"
  else
    printf '{}' > "${tmp}"
  fi
  jq "$@" "${filter}" "${tmp}" > "${tmp}.new"
  mv "${tmp}.new" "${cfg}"
  rm -f "${tmp}"
}

# ---------------------------------------------------------------------------
# Binary install
# ---------------------------------------------------------------------------

install_binary() {
  if [[ ! -d "${MCP_REPO}" ]]; then
    log_skip "repo not found at ${MCP_REPO}; skipping binary install"
    return 0
  fi
  log "installing personal-mcp to ~/.local/bin ..."
  if cargo install --path "${MCP_REPO}" --root "${HOME_DIR}/.local" --force; then
    log_ok "installed ${MCP_BIN}"
    if [[ "${KEEP_BUILD_ARTIFACTS:-0}" != "1" ]]; then
      log "cleaning build artifacts..."
      cargo clean --manifest-path "${MCP_REPO}/Cargo.toml" 2>/dev/null || true
    fi
    return 0
  fi

  if [[ -x "${MCP_BIN}" ]]; then
    log_warn "cargo install failed; using existing binary at ${MCP_BIN}"
    return 0
  fi

  log_err "cargo install failed and no existing binary found at ${MCP_BIN}"
  return 1
}

install_opencode_if_missing() {
  if command -v opencode >/dev/null 2>&1; then
    log_skip "opencode already installed: $(command -v opencode)"
    return 0
  fi
  if command -v zb >/dev/null 2>&1; then
    log "installing opencode via zerobrew ..."
    zb install opencode || {
      log_warn "failed to install opencode via zerobrew; continuing"
      return 0
    }
    log_ok "opencode installed: $(command -v opencode)"
    return 0
  fi
  if command -v brew >/dev/null 2>&1; then
    log "installing opencode via brew ..."
    brew install opencode || {
      log_warn "failed to install opencode via brew; continuing"
      return 0
    }
    log_ok "opencode installed: $(command -v opencode)"
    return 0
  fi
  log_skip "opencode not found and no brew-compatible installer (zb/brew) is available"
}

# ---------------------------------------------------------------------------
# Per-tool MCP / config merges
# ---------------------------------------------------------------------------

configure_claude_desktop() {
  merge_json_config "${CLAUDE_DESKTOP_CFG}" '
    .mcpServers = (.mcpServers // {}) |
    .mcpServers.personal = {
      "type": "stdio",
      "command": $cmd,
      "args": [],
      "env": {
        "MCP_CTX_DIR": $mcp_ctx,
        "MCP_ENV_FILE": $mcp_env_file,
        "BAML_LOG": $baml_log,
        "BOUNDARY_MAX_LOG_CHUNK_CHARS": $baml_max_chars
      }
    }
  ' \
    --arg cmd "${MCP_BIN}" \
    --arg mcp_ctx "${MCP_CTX_DIR}" \
    --arg mcp_env_file "${MCP_ENV_FILE_PATH}" \
    --arg baml_log "${BAML_LOG_DEFAULT}" \
    --arg baml_max_chars "${BOUNDARY_MAX_LOG_CHUNK_CHARS_DEFAULT}"
  log_ok "updated Claude Desktop: ${CLAUDE_DESKTOP_CFG}"
}

configure_claude_code() {
  merge_json_config "${CLAUDE_CODE_CFG}" '
    .cleanupPeriodDays = (.cleanupPeriodDays // 30) |
    .includeCoAuthoredBy = (.includeCoAuthoredBy // true) |
    .env = (.env // {}) |
    .env.BAML_LOG = (.env.BAML_LOG // $baml_log) |
    .env.BOUNDARY_MAX_LOG_CHUNK_CHARS = (.env.BOUNDARY_MAX_LOG_CHUNK_CHARS // $baml_max_chars) |
    .env.MCP_ENV_FILE = (.env.MCP_ENV_FILE // $mcp_env_file) |
    .permissions = (.permissions // {}) |
    .permissions.defaultMode = (.permissions.defaultMode // "acceptEdits")
  ' \
    --arg baml_log "${BAML_LOG_DEFAULT}" \
    --arg baml_max_chars "${BOUNDARY_MAX_LOG_CHUNK_CHARS_DEFAULT}" \
    --arg mcp_env_file "${MCP_ENV_FILE_PATH}"
  log_ok "updated Claude Code: ${CLAUDE_CODE_CFG}"
}

configure_cursor() {
  merge_json_config "${CURSOR_CFG}" '
    .mcpServers = (.mcpServers // {}) |
    .mcpServers.personal = {
      "command": $cmd,
      "args": [],
      "env": {
        "MCP_CTX_DIR": $mcp_ctx,
        "MCP_ENV_FILE": $mcp_env_file,
        "BAML_LOG": $baml_log,
        "BOUNDARY_MAX_LOG_CHUNK_CHARS": $baml_max_chars
      }
    }
  ' \
    --arg cmd "${MCP_BIN}" \
    --arg mcp_ctx "${MCP_CTX_DIR}" \
    --arg mcp_env_file "${MCP_ENV_FILE_PATH}" \
    --arg baml_log "${BAML_LOG_DEFAULT}" \
    --arg baml_max_chars "${BOUNDARY_MAX_LOG_CHUNK_CHARS_DEFAULT}"
  log_ok "updated Cursor: ${CURSOR_CFG}"
}

configure_zed() {
  merge_json_config "${ZED_CFG}" '
    .context_servers = (.context_servers // {}) |
    .context_servers.personal = {
      "command": $cmd,
      "args": [],
      "env": {
        "MCP_CTX_DIR": $mcp_ctx,
        "MCP_ENV_FILE": $mcp_env_file,
        "BAML_LOG": $baml_log,
        "BOUNDARY_MAX_LOG_CHUNK_CHARS": $baml_max_chars
      }
    }
  ' \
    --arg cmd "${MCP_BIN}" \
    --arg mcp_ctx "${MCP_CTX_DIR}" \
    --arg mcp_env_file "${MCP_ENV_FILE_PATH}" \
    --arg baml_log "${BAML_LOG_DEFAULT}" \
    --arg baml_max_chars "${BOUNDARY_MAX_LOG_CHUNK_CHARS_DEFAULT}"
  log_ok "updated Zed: ${ZED_CFG}"
}

configure_opencode() {
  merge_json_config "${OPENCODE_CFG}" '
    ."$schema" = (."$schema" // "https://opencode.ai/config.json") |
    .mcp = (.mcp // {}) |
    .mcp.personal = ((.mcp.personal // {
      "type": "local",
      "command": [$cmd],
      "enabled": true,
      "environment": {
        "MCP_CTX_DIR": $mcp_ctx,
        "MCP_ENV_FILE": $mcp_env_file,
        "BAML_LOG": $baml_log,
        "BOUNDARY_MAX_LOG_CHUNK_CHARS": $baml_max_chars
      }
    }) | .environment = (.environment // {}) |
      .environment.MCP_CTX_DIR = (.environment.MCP_CTX_DIR // $mcp_ctx) |
      .environment.MCP_ENV_FILE = (.environment.MCP_ENV_FILE // $mcp_env_file) |
      .environment.BAML_LOG = (.environment.BAML_LOG // $baml_log) |
      .environment.BOUNDARY_MAX_LOG_CHUNK_CHARS = (.environment.BOUNDARY_MAX_LOG_CHUNK_CHARS // $baml_max_chars))
  ' \
    --arg cmd "${MCP_BIN}" \
    --arg mcp_ctx "${MCP_CTX_DIR}" \
    --arg mcp_env_file "${MCP_ENV_FILE_PATH}" \
    --arg baml_log "${BAML_LOG_DEFAULT}" \
    --arg baml_max_chars "${BOUNDARY_MAX_LOG_CHUNK_CHARS_DEFAULT}"
  log_ok "updated OpenCode: ${OPENCODE_CFG}"
}

configure_codex() {
  # Codex uses TOML — handle with awk + append.
  touch "${CODEX_CFG}"
  local tmp
  tmp="$(mktemp)"

  # Strip existing personal MCP sections so we can rewrite them.
  awk '
    BEGIN { skip = 0 }
    /^\[mcp_servers\.personal\]$/ { skip = 1; next }
    /^\[mcp_servers\.personal\.env\]$/ { skip = 1; next }
    skip == 1 && /^\[/ { skip = 0 }
    skip == 0 { print }
  ' "${CODEX_CFG}" > "${tmp}"

  cat >> "${tmp}" <<EOF

[mcp_servers.personal]
command = "${MCP_BIN}"
args = []

[mcp_servers.personal.env]
MCP_CTX_DIR = "${MCP_CTX_DIR}"
MCP_ENV_FILE = "${MCP_ENV_FILE_PATH}"
BAML_LOG = "${BAML_LOG_DEFAULT}"
BOUNDARY_MAX_LOG_CHUNK_CHARS = "${BOUNDARY_MAX_LOG_CHUNK_CHARS_DEFAULT}"

EOF
  mv "${tmp}" "${CODEX_CFG}"
  log_ok "updated Codex: ${CODEX_CFG}"
}

configure_gemini() {
  merge_json_config "${GEMINI_CFG}" '
    .theme = (.theme // "Default") |
    .mcpServers = (.mcpServers // {}) |
    .mcpServers.personal = ((.mcpServers.personal // {
      "command": $cmd,
      "args": [],
      "env": {
        "MCP_CTX_DIR": $mcp_ctx,
        "MCP_ENV_FILE": $mcp_env_file,
        "BAML_LOG": $baml_log,
        "BOUNDARY_MAX_LOG_CHUNK_CHARS": $baml_max_chars
      }
    }) | .env = (.env // {}) |
      .env.MCP_CTX_DIR = (.env.MCP_CTX_DIR // $mcp_ctx) |
      .env.MCP_ENV_FILE = (.env.MCP_ENV_FILE // $mcp_env_file) |
      .env.BAML_LOG = (.env.BAML_LOG // $baml_log) |
      .env.BOUNDARY_MAX_LOG_CHUNK_CHARS = (.env.BOUNDARY_MAX_LOG_CHUNK_CHARS // $baml_max_chars))
  ' \
    --arg cmd "${MCP_BIN}" \
    --arg mcp_ctx "${MCP_CTX_DIR}" \
    --arg mcp_env_file "${MCP_ENV_FILE_PATH}" \
    --arg baml_log "${BAML_LOG_DEFAULT}" \
    --arg baml_max_chars "${BOUNDARY_MAX_LOG_CHUNK_CHARS_DEFAULT}"
  log_ok "updated Gemini: ${GEMINI_CFG}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  ensure_dirs
  install_binary
  install_opencode_if_missing
  command -v jq >/dev/null 2>&1 || { log_err "jq required"; exit 1; }
  configure_claude_desktop
  configure_claude_code
  configure_cursor
  configure_zed
  configure_opencode
  configure_codex
  configure_gemini
  log_ok "done — restart Claude/Cursor/Zed/OpenCode/Codex/Gemini to load updated configs"
}

main "$@"
