#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/dryrun.sh"
TAG="claude-log-retention"

AI_LOG_ROOT="${AI_LOG_ROOT:-${HOME}/logs/ai}"
RETENTION_DAYS="${AI_LOG_RETENTION_DAYS:-180}"
COMPRESS_AFTER_DAYS="${AI_LOG_COMPRESS_AFTER_DAYS:-14}"

usage() {
  cat <<'EOF'
Usage: claude-log-retention.sh [options]

Options:
  --root <path>                  Root directory (default: ~/logs/ai)
  --retention-days <n>           Days to keep daily shards (default: 180)
  --compress-after-days <n>      Compress events.jsonl after N days (default: 14)
  --dry-run                      Print actions without changing files
  -h, --help                     Show this help

Environment overrides:
  AI_LOG_ROOT
  AI_LOG_RETENTION_DAYS
  AI_LOG_COMPRESS_AFTER_DAYS
EOF
}

is_non_negative_int() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      AI_LOG_ROOT="$2"
      shift 2
      ;;
    --retention-days)
      RETENTION_DAYS="$2"
      shift 2
      ;;
    --compress-after-days)
      COMPRESS_AFTER_DAYS="$2"
      shift 2
      ;;
    --dry-run)
      set_dryrun_mode 1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_err "unknown argument: $1"
      usage >&2
      exit 1
      ;;
  esac
done

if ! is_non_negative_int "$RETENTION_DAYS"; then
  log_err "invalid retention days: $RETENTION_DAYS"
  exit 1
fi

if ! is_non_negative_int "$COMPRESS_AFTER_DAYS"; then
  log_err "invalid compress-after days: $COMPRESS_AFTER_DAYS"
  exit 1
fi

if [[ ! -d "$AI_LOG_ROOT" ]]; then
  log_skip "log root does not exist: $AI_LOG_ROOT"
  exit 0
fi

if is_dryrun; then
  log "dry-run mode enabled"
fi

log "processing log directory: $AI_LOG_ROOT"
log "retention: ${RETENTION_DAYS} days, compress after: ${COMPRESS_AFTER_DAYS} days"

NOW_EPOCH="$(date +%s)"
compressed_count=0
deleted_count=0

for day_dir in "$AI_LOG_ROOT"/*; do
  [[ -d "$day_dir" ]] || continue

  day_name="$(basename "$day_dir")"
  [[ "$day_name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || continue

  day_epoch="$(date -j -f '%Y-%m-%d' "$day_name" '+%s' 2>/dev/null || date -d "$day_name" '+%s' 2>/dev/null || true)"
  [[ -n "$day_epoch" ]] || continue

  age_days=$(( (NOW_EPOCH - day_epoch) / 86400 ))

  if (( age_days >= COMPRESS_AFTER_DAYS )); then
    while IFS= read -r file; do
      dryrun_exec gzip -f "$file"
      ((compressed_count++))
    done < <(find "$day_dir" -type f -name 'events.jsonl')
  fi

  if (( age_days >= RETENTION_DAYS )); then
    dryrun_exec rm -rf "$day_dir"
    ((deleted_count++))
  fi
done

if [[ $compressed_count -gt 0 ]]; then
  log_ok "compressed $compressed_count file(s)"
fi

if [[ $deleted_count -gt 0 ]]; then
  log_ok "deleted $deleted_count directory(ies)"
fi

if [[ $compressed_count -eq 0 && $deleted_count -eq 0 ]]; then
  log_skip "no files to compress or delete"
fi
