#!/usr/bin/env bash
# PostToolUse hook: detect secrets in bash output and warn Claude.
# Reads tool JSON on stdin. If redact changes the output, emits a message.

set -euo pipefail

INPUT=$(cat)

# Extract bash output — CC sends stdout/stderr fields (not output)
OUTPUT=$(python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    resp = d.get('tool_response', {})
    out = resp.get('stdout', '') or resp.get('output', '')
    print(out, end='')
except Exception:
    pass
" <<< "$INPUT" 2>/dev/null || true)

if [ -z "$OUTPUT" ]; then
    echo '{"decision": "allow"}'
    exit 0
fi

# Check if redact changes anything (secrets present).
# Suppress ALL stderr — redact has a broken ssn_us regex that warns on every run.
REDACTED=$(echo "$OUTPUT" | redact --level minimal 2>/dev/null || echo "$OUTPUT")

if [ "$OUTPUT" = "$REDACTED" ]; then
    echo '{"decision": "allow"}'
    exit 0
fi

# Secrets found — emit redacted output as a message to Claude
MSG=$(REDACTED="$REDACTED" python3 -c "
import sys, json, os
redacted = os.environ['REDACTED']
msg = '[redact] Output contained secrets — redacted version:\n\n' + redacted
print(json.dumps({'decision': 'allow', 'message': msg}))
")

echo "$MSG"
