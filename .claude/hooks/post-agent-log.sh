#!/usr/bin/env bash
# PostToolUse hook: log joe suite agent dispatches to ~/.claude/logs/agent-sessions.jsonl
# Fires on Agent tool use. Captures: agent name, description, timestamp.

set -euo pipefail

LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/agent-sessions.jsonl"
mkdir -p "$LOG_DIR"

INPUT=$(cat)

python3 -c "
import sys, json, os
from datetime import datetime, timezone

d = json.load(sys.stdin)
params = d.get('tool_input', {})

# Only log joe suite agents
SUITE = {'forge', 'sentinel', 'navigator', 'conductor'}
agent_type = params.get('subagent_type', '')
description = params.get('description', '')
prompt = params.get('prompt', '')

# Detect suite agent: explicit subagent_type, or agent name in description/prompt
agent = None
for name in SUITE:
    if agent_type == name:
        agent = name
        break
    if name in description.lower() or f'@{name}' in prompt.lower():
        agent = name
        break

if agent is None:
    sys.exit(0)

entry = {
    'ts': datetime.now(timezone.utc).isoformat(),
    'agent': agent,
    'description': description[:200],
    'cwd': os.environ.get('PWD', ''),
}

log_file = os.path.expanduser('~/.claude/logs/agent-sessions.jsonl')
with open(log_file, 'a') as f:
    f.write(json.dumps(entry) + '\n')
" <<< "$INPUT" 2>/dev/null || true

echo '{"decision": "allow"}'
