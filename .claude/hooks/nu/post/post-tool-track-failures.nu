#!/usr/bin/env nu
# post-tool-track-failures.nu — PostToolUse/Bash hook
# Records Bash commands that exit non-zero into the state file consumed by
# pre-tool-course-correct.nu for learned course correction.

const HOOKS_DIR = ($nu.current-exe | path dirname)  # resolved at load time
const RULES_FILE = ($env.HOME | path join ".claude" "hooks" "course-correct-rules.json")
const DEFAULT_STATE_FILE = ($env.HOME | path join ".claude" "hooks" "course-correct-state.json")

# Exit codes that mean "user or OS interrupted" — not a logic failure worth tracking
const SIGNAL_EXIT_CODES = [130, 137, 143]

# Patterns for commands that fail by design
const EXCLUDE_PATTERNS = [
    '^\s*false\s*$'
    '\|\|\s*(true|:)\s*$'
    ';\s*(true|:)\s*$'
    '^\s*\['
    '\btest\s+-[defhlrswxz]\b'
    '2>/dev/null'
    '>/dev/null\s+2>&1'
]

def load_rules [] {
    try {
        open $RULES_FILE | from json
    } catch {
        {failure_learning: {enabled: false}}
    }
}

def load_state [state_path: string] {
    try {
        open $state_path | from json
    } catch {
        {failures: {}}
    }
}

def save_state [state_path: string, state: record] {
    let tmp = $"($state_path).tmp"
    try {
        $state | to json | save --force $tmp
        mv --force $tmp $state_path
    } catch {
        try { rm -f $tmp } catch { }
    }
}

def command_key [command: string] {
    $command | hash sha256
}

def should_track [command: string, exit_code: int] {
    if $exit_code in $SIGNAL_EXIT_CODES { return false }
    for pat in $EXCLUDE_PATTERNS {
        if ($command =~ $pat) { return false }
    }
    true
}

def prune_state [state: record, window: int, max_entries: int, cleanup_after: int] {
    let now = (date now | into int) / 1_000_000_000  # unix timestamp in seconds
    mut failures = $state.failures

    # Remove stale entries (last_seen too old)
    let stale_keys = ($failures | transpose key value
        | where { |row| ($now - ($row.value | get -i last_seen | default 0)) > $cleanup_after }
        | get key)
    for k in $stale_keys { $failures = ($failures | reject $k) }

    # Prune old timestamps, remove entries with no recent timestamps
    let empty_keys = ($failures | transpose key value | each { |row|
        let recent = ($row.value.timestamps | where { |t| ($now - $t) <= $window })
        if ($recent | is-empty) { $row.key } else { null }
    } | where { |v| $v != null })
    for k in $empty_keys { $failures = ($failures | reject $k) }

    # Evict oldest if over max_entries
    if ($failures | length) > $max_entries {
        let by_age = ($failures | transpose key value
            | sort-by { |row| $row.value | get -i last_seen | default 0 }
            | first (($failures | length) - $max_entries)
            | get key)
        for k in $by_age { $failures = ($failures | reject $k) }
    }

    $state | upsert failures $failures
}

def main [] {
    let input = try { $in | from json } catch { exit 0 }

    if ($input | get -i tool_name | default "") != "Bash" { exit 0 }

    let tool_response = $input | get -i tool_response | default {}
    let exit_code = $tool_response | get -i exit_code | default 0 | into int
    if $exit_code == 0 { exit 0 }

    let command = $input | get -i tool_input.command | default ""
    if $command == "" { exit 0 }
    if not (should_track $command $exit_code) { exit 0 }

    let config = load_rules
    let fl_config = $config | get -i failure_learning | default {}
    if not ($fl_config | get -i enabled | default true) { exit 0 }

    let window = $fl_config | get -i window_seconds | default 300 | into int
    let max_entries = $fl_config | get -i max_tracked_commands | default 200 | into int
    let cleanup_after = $fl_config | get -i cleanup_after_seconds | default 3600 | into int
    let state_path = $fl_config | get -i state_file | default $DEFAULT_STATE_FILE

    mut state = load_state $state_path
    let now = (date now | into int) / 1_000_000_000
    let key = command_key $command

    mut failures = $state | get -i failures | default {}
    let existing = $failures | get -i $key | default {
        command_preview: ($command | str substring 0..80)
        timestamps: []
        last_seen: 0.0
    }
    let updated_entry = $existing
        | upsert timestamps ($existing.timestamps ++ [$now])
        | upsert last_seen $now
        | upsert command_preview ($command | str substring 0..80)

    $failures = ($failures | upsert $key $updated_entry)
    $state = ($state | upsert failures $failures)
    $state = (prune_state $state $window $max_entries $cleanup_after)
    save_state $state_path $state
}
