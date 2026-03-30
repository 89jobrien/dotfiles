#!/usr/bin/env bats
# Vector fd exhaustion regression tests
# Verifies the subagent glob exclude prevents "Too many open files" scenarios

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  VECTOR_CONFIG="$REPO_ROOT/vector/.config/vector/vector.yaml"
  TMP="$BATS_TMPDIR/vector-fd-test"
  mkdir -p "$TMP"
}

teardown() {
  rm -rf "$TMP"
}

# ── Config validation ────────────────────────────────────────────────────────

@test "vector config is valid" {
  if ! command -v vector &>/dev/null; then
    skip "vector not in PATH"
  fi
  mkdir -p "$HOME/.local/state/vector"
  run vector validate "$VECTOR_CONFIG"
  [ "$status" -eq 0 ]
}

@test "vector config includes subagent exclude patterns" {
  run grep -c "subagents" "$VECTOR_CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

# ── Glob exclude logic (simulated) ──────────────────────────────────────────

@test "subagent files are excluded by pattern" {
  # Create session files mirroring real layout
  mkdir -p "$TMP/projects/proj-a/subagents"
  mkdir -p "$TMP/projects/proj-b/subagents"
  touch "$TMP/projects/proj-a/session-main.jsonl"
  touch "$TMP/projects/proj-a/subagents/agent-abc123.jsonl"
  touch "$TMP/projects/proj-a/subagents/agent-def456.jsonl"
  touch "$TMP/projects/proj-b/session-main.jsonl"
  touch "$TMP/projects/proj-b/subagents/agent-xyz789.jsonl"

  # Count all JSONL files
  all_count=$(find "$TMP/projects" -name "*.jsonl" | wc -l | tr -d ' ')
  # Count with subagents excluded
  excluded_count=$(find "$TMP/projects" -name "*.jsonl" \
    ! -path "*/subagents/*" | wc -l | tr -d ' ')

  # 5 total, 3 subagent files excluded, 2 remain
  [ "$all_count" -eq 5 ]
  [ "$excluded_count" -eq 2 ]
}

@test "subagent ratio at scale stays below fd danger threshold" {
  # Simulate the scale that caused the original bug (1143 subagent / 1549 total)
  mkdir -p "$TMP/projects/big-project/subagents"

  # Create 100 session + 743 subagent files (proportional to real ratio)
  for i in $(seq 1 100); do
    touch "$TMP/projects/big-project/session-$i.jsonl"
  done
  for i in $(seq 1 743); do
    touch "$TMP/projects/big-project/subagents/agent-$i.jsonl"
  done

  total=$(find "$TMP/projects" -name "*.jsonl" | wc -l | tr -d ' ')
  after_exclude=$(find "$TMP/projects" -name "*.jsonl" \
    ! -path "*/subagents/*" | wc -l | tr -d ' ')

  # Without exclude: 843 files (would hit default 256 fd limit)
  [ "$total" -eq 843 ]
  # With exclude: only 100 session files — well under 256
  [ "$after_exclude" -eq 100 ]
  [ "$after_exclude" -lt 256 ]
}

# ── Plist fd limits ──────────────────────────────────────────────────────────

@test "launchd plist sets NumberOfFiles to at least 1024" {
  PLIST="$HOME/Library/LaunchAgents/com.rentamac.vector.plist"
  if [[ ! -f "$PLIST" ]]; then
    skip "vector launchd plist not installed"
  fi

  run python3 -c "
import plistlib, sys
with open('$PLIST', 'rb') as f:
    p = plistlib.load(f)
soft = p.get('SoftResourceLimits', {}).get('NumberOfFiles', 0)
hard = p.get('HardResourceLimits', {}).get('NumberOfFiles', 0)
print(f'soft={soft} hard={hard}')
sys.exit(0 if soft >= 1024 and hard >= 1024 else 1)
"
  [ "$status" -eq 0 ]
}

@test "vector-service.sh install template includes NumberOfFiles limit" {
  run grep -c "NumberOfFiles" "$REPO_ROOT/scripts/vector-service.sh"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}
