#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${AI_LOG_ROOT:-${HOME}/logs/ai}"
RETENTION_DAYS="${AI_LOG_RETENTION_DAYS:-180}"
COMPRESS_AFTER_DAYS="${AI_LOG_COMPRESS_AFTER_DAYS:-14}"
DRY_RUN=0

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

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT_DIR="$2"
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
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! is_non_negative_int "$RETENTION_DAYS"; then
  printf 'Invalid retention days: %s\n' "$RETENTION_DAYS" >&2
  exit 1
fi

if ! is_non_negative_int "$COMPRESS_AFTER_DAYS"; then
  printf 'Invalid compress-after days: %s\n' "$COMPRESS_AFTER_DAYS" >&2
  exit 1
fi

if [[ ! -d "$ROOT_DIR" ]]; then
  printf 'Log root does not exist, nothing to do: %s\n' "$ROOT_DIR"
  exit 0
fi

NOW_EPOCH="$(date +%s)"

for day_dir in "$ROOT_DIR"/*; do
  [[ -d "$day_dir" ]] || continue

  day_name="$(basename "$day_dir")"
  [[ "$day_name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || continue

  day_epoch="$(date -j -f '%Y-%m-%d' "$day_name" '+%s' 2>/dev/null || date -d "$day_name" '+%s' 2>/dev/null || true)"
  [[ -n "$day_epoch" ]] || continue

  age_days=$(( (NOW_EPOCH - day_epoch) / 86400 ))

  if (( age_days >= COMPRESS_AFTER_DAYS )); then
    while IFS= read -r file; do
      run gzip -f "$file"
    done < <(find "$day_dir" -type f -name 'events.jsonl')
  fi

  if (( age_days >= RETENTION_DAYS )); then
    run rm -rf "$day_dir"
  fi
done
