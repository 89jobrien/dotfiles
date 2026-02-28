#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STOW_LIST_FILE="${ROOT_DIR}/config/stow-packages.txt"

status=0

echo "[drift] repo=${ROOT_DIR}"

if ! git -C "${ROOT_DIR}" diff --quiet || ! git -C "${ROOT_DIR}" diff --cached --quiet; then
  echo "[drift] dotfiles repo has uncommitted changes"
  status=1
fi

if command -v stow >/dev/null 2>&1 && [[ -f "${STOW_LIST_FILE}" ]]; then
  while IFS= read -r pkg; do
    [[ -z "${pkg}" || "${pkg}" =~ ^[[:space:]]*# ]] && continue
    if stow -d "${ROOT_DIR}" -t "${HOME}" -n "${pkg}" 2>&1 | grep -Eq 'WARNING|ERROR'; then
      echo "[drift] stow conflict for package: ${pkg}"
      status=1
    fi
  done < "${STOW_LIST_FILE}"
fi

if [[ $status -ne 0 ]]; then
  echo "[drift] FAIL"
  exit 1
fi

echo "[drift] PASS"
