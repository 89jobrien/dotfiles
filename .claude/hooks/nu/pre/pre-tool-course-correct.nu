#!/usr/bin/env nu
# pre-tool-course-correct.nu — PreToolUse hook
# Checks Bash tool calls against predefined rules and learned repeated failures.

def rules_file [] { $env.HOME | path join ".claude" "hooks" "course-correct-rules.json" }
def default_state_file [] { $env.HOME | path join ".claude" "hooks" "course-correct-state.json" }

def load_rules [] {
    try { open (rules_file) | from json } catch { {rules: [], failure_learning: {enabled: false}} }
}

def load_state [state_path: string] {
    try { open $state_path | from json } catch { {failures: {}} }
}

def deny [message: string] {
    let payload = {
        hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny"}
        systemMessage: $"[JOEHOOK] ($message)"
    }
    print --stderr ($payload | to json)
    exit 2
}

def check_rules [command: string, rules: list] {
    for rule in $rules {
        if not ($rule | get -i enabled | default true) { continue }

        let flags_str = $rule | get -i pattern_flags | default ""
        let pattern = if ("i" in $flags_str) or ("(?i)" in $flags_str) {
            $"(?i)($rule.pattern)"
        } else {
            $rule.pattern
        }

        let matched = try { $command =~ $pattern } catch { false }
        if not $matched { continue }

        # Check exceptions
        let excepted = ($rule | get -i exceptions | default [] | any { |exc|
            try { $command =~ $exc } catch { false }
        })
        if $excepted { continue }

        return ($rule | get -i message | default $"Blocked by rule '($rule | get -i id | default "?")'.")
    }
    null
}

def command_key [command: string] {
    $command | hash sha256
}

def check_learned_failures [command: string, fl_config: record, state: record] {
    if not ($fl_config | get -i enabled | default true) { return null }

    let threshold = $fl_config | get -i block_threshold | default 3 | into int
    let window = $fl_config | get -i window_seconds | default 300 | into int
    let now = (date now | into int) / 1_000_000_000

    let key = command_key $command
    let entry = $state | get -i failures | default {} | get -i $key

    if $entry == null { return null }

    let recent = ($entry.timestamps | where { |t| ($now - $t) <= $window })
    if ($recent | length) < $threshold { return null }

    let window_minutes = [1, ($window // 60)] | math max
    let template = $fl_config | get -i message_template | default "[course-correct] This command has failed {count} times in the last {window} minutes. Try a different approach.\n\nFailing command: {preview}"
    let preview = $entry | get -i command_preview | default ($command | str substring 0..80)

    $template
        | str replace "{count}" ($recent | length | into string)
        | str replace "{window}" ($window_minutes | into string)
        | str replace "{preview}" $preview
}

def main [] {
    let input = try { open --raw /dev/stdin | from json } catch { exit 0 }

    if ($input | get -i tool_name | default "") != "Bash" { exit 0 }

    let command = $input | get -i tool_input.command | default ""
    if $command == "" { exit 0 }

    let config = load_rules
    let rules = $config | get -i rules | default []
    let fl_config = $config | get -i failure_learning | default {}

    # 1. Predefined rules
    let block_msg = check_rules $command $rules
    if $block_msg != null { deny $block_msg }

    # 2. Learned failures
    if ($fl_config | get -i enabled | default true) {
        let state_path = $fl_config | get -i state_file | default (default_state_file)
        let state = load_state $state_path
        let learned_msg = check_learned_failures $command $fl_config $state
        if $learned_msg != null { deny $learned_msg }
    }
}
