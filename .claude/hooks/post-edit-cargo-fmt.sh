#!/usr/bin/env bash
# post-edit-cargo-fmt.sh
# PostToolUse hook: runs `cargo fmt` on the workspace when a .rs file is edited.
# Receives tool use JSON on stdin.

set -euo pipefail

# Parse file_path from stdin JSON
FILE_PATH=$(cat | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', ''))
except Exception:
    print('')
" 2>/dev/null)

# Only act on .rs files
[[ "$FILE_PATH" == *.rs ]] || exit 0

# Walk up from the file to find the workspace root (Cargo.toml with [workspace])
DIR=$(dirname "$FILE_PATH")
WORKSPACE_ROOT=""

while [[ "$DIR" != "/" ]]; do
    if [[ -f "$DIR/Cargo.toml" ]]; then
        if grep -q '^\[workspace\]' "$DIR/Cargo.toml" 2>/dev/null; then
            WORKSPACE_ROOT="$DIR"
            break
        fi
        # Single-crate root (no [workspace]) — use this dir
        if [[ -z "$WORKSPACE_ROOT" ]]; then
            WORKSPACE_ROOT="$DIR"
        fi
    fi
    DIR=$(dirname "$DIR")
done

[[ -n "$WORKSPACE_ROOT" ]] || exit 0

# Run cargo fmt (non-blocking — don't fail the tool use if fmt errors)
cd "$WORKSPACE_ROOT"
cargo fmt --all 2>/dev/null || true
