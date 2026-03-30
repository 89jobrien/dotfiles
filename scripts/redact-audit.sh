#!/usr/bin/env bash
# redact-audit.sh — scan files for sensitive data and log findings as JSONL
#
# Usage:
#   scripts/redact-audit.sh [--verbose] [--hook NAME] [--staged] [FILE...]
#
# Modes:
#   --staged       scan files currently staged in git (default when no files given)
#   FILE...        scan explicit file paths
#
# Options:
#   --verbose, -v  print findings to stderr (default: log-only)
#   --hook NAME    label for the hook field in audit log (default: manual)
#
# Exit code: always 0 (audit-only, never blocks)
#
# Log: .logs/redact-audit.jsonl (one JSON object per pattern hit per file)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="${ROOT_DIR}/.logs/redact-audit.jsonl"
CONFIG="${ROOT_DIR}/config/obfsck-secrets.yaml"

# ── Tier mapping: group name → tier ──────────────────────────────────────────
# Groups are defined in config/obfsck-secrets.yaml.
# Tiers: critical > high > medium > low
declare -A TIER_MAP=(
  [private_keys]="critical"
  [bearer_tokens]="critical"
  [ai_apis]="high"
  [cloud_credentials]="high"
  [onepassword]="high"
  [pii]="medium"
  [personal_env]="low"
)

# ── Text file extensions to scan ─────────────────────────────────────────────
TEXT_EXTS=(
  md txt yaml yml toml json env conf log jsonl
  Justfile Makefile
)

# ── Arg parsing ──────────────────────────────────────────────────────────────
VERBOSE=false
HOOK_NAME="manual"
STAGED=false
FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose|-v) VERBOSE=true; shift ;;
    --hook)       HOOK_NAME="$2"; shift 2 ;;
    --staged)     STAGED=true; shift ;;
    -*)           echo "unknown option: $1" >&2; exit 1 ;;
    *)            FILES+=("$1"); shift ;;
  esac
done

# ── Resolve file list ─────────────────────────────────────────────────────────
if [[ ${#FILES[@]} -eq 0 ]]; then
  STAGED=true
fi

if [[ "$STAGED" == true ]]; then
  while IFS= read -r f; do
    FILES+=("$f")
  done < <(git -C "$ROOT_DIR" diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  exit 0
fi

# ── Helpers ──────────────────────────────────────────────────────────────────
is_text_file() {
  local f="$1"
  local base
  base="$(basename "$f")"
  local ext="${base##*.}"

  # Extensionless files matched by basename
  for t in "${TEXT_EXTS[@]}"; do
    [[ "$base" == "$t" ]] && return 0
    [[ "$ext"  == "$t" ]] && return 0
  done

  # mise task files
  [[ "$base" == ".mise.toml" || "$base" == "mise.toml" || "$base" == "mise.local.toml" ]] && return 0

  return 1
}

# Resolve label → group using config file (grep for proximity)
label_to_group() {
  local label="$1"
  # Strip [REDACTED-...] wrapper → extract inner label
  label="${label#\[REDACTED-}"
  label="${label%\]}"
  # Search config for the label value and grab the nearest group heading above it
  awk -v lbl="$label" '
    /^  [a-z_]+:$/ { group = substr($1, 1, length($1)-1) }
    /label:/ && $0 ~ lbl { print group; exit }
  ' "$CONFIG"
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

commit_ref() {
  git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo "unborn"
}

mkdir -p "$(dirname "$LOG_FILE")"

COMMIT="$(commit_ref)"
TIMESTAMP="$(now_iso)"
TOTAL_HITS=0

# ── Scan ──────────────────────────────────────────────────────────────────────
for rel_path in "${FILES[@]}"; do
  # Resolve absolute path: explicit absolute paths pass through; relative paths prepend ROOT_DIR
  if [[ "$rel_path" == /* ]]; then
    abs_path="$rel_path"
  else
    abs_path="${ROOT_DIR}/${rel_path}"
  fi
  [[ -f "$abs_path" ]] || continue
  is_text_file "$rel_path" || continue

  # Capture staged content (pre-commit) or file content (manual)
  if [[ "$STAGED" == true && "$rel_path" != /* ]]; then
    content="$(git -C "$ROOT_DIR" show ":${rel_path}" 2>/dev/null)" || continue
  else
    content="$(cat "$abs_path")"
  fi

  [[ -z "$content" ]] && continue

  # Run redact --audit; audit report → stderr, redacted content → stdout
  audit_report="$(printf '%s\n' "$content" \
    | obfsck --config "$CONFIG" --audit 2>&1 >/dev/null)" || true

  # Parse: "  [REDACTED-LABEL]    N"
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]+\[REDACTED-([A-Z0-9_-]+)\][[:space:]]+([0-9]+)$ ]]; then
      label="${BASH_REMATCH[1]}"
      count="${BASH_REMATCH[2]}"
      group="$(label_to_group "[REDACTED-${label}]")"
      tier="${TIER_MAP[$group]:-unknown}"

      entry="$(printf '{"ts":"%s","hook":"%s","commit":"%s","file":"%s","tier":"%s","group":"%s","label":"%s","match_count":%s}' \
        "$TIMESTAMP" "$HOOK_NAME" "$COMMIT" "$rel_path" "$tier" "$group" "$label" "$count")"

      echo "$entry" >> "$LOG_FILE"
      TOTAL_HITS=$(( TOTAL_HITS + count ))

      if [[ "$VERBOSE" == true ]]; then
        printf '[redact-audit] %s tier=%s group=%s label=%s count=%s\n' \
          "$rel_path" "$tier" "$group" "$label" "$count" >&2
      fi
    fi
  done <<< "$audit_report"
done

if [[ "$VERBOSE" == true && "$TOTAL_HITS" -gt 0 ]]; then
  printf '[redact-audit] %d total match(es) logged to %s\n' \
    "$TOTAL_HITS" "${LOG_FILE#"$ROOT_DIR"/}" >&2
fi

exit 0
