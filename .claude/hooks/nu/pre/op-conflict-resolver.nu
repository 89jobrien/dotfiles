#!/usr/bin/env nu
# op-conflict-resolver.nu — PreToolUse hook
# Detects environment variable conflicts when using `op run`.
# Blocks the command and returns the corrected command with `env -u` flags.

def deny [message: string] {
    let payload = {
        hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny"}
        systemMessage: $"[JOEHOOK] ($message)"
    }
    print --stderr ($payload | to json)
    exit 2
}

def find_direct_env_conflicts [] {
    # Return names of env vars whose current value starts with 'op://'
    $env | transpose key value
        | where { |row| (($row.value | describe) == "string" and ($row.value | str starts-with "op://")) }
        | get key
}

def find_env_file_conflicts [command: string] {
    # If command contains --env-file <path>, read that file and find conflicts
    let match = ($command | parse --regex "--env-file[=\\s]+([\"']?)(\\S+)\\1")
    if ($match | is-empty) { return [] }

    let env_file = $match | first | get capture2
    let expanded = $env_file | path expand

    if not ($expanded | path exists) { return [] }

    let conflicts = try {
        let env_keys = ($env | transpose key value | get key)
        (open $expanded | lines
            | where { |l| (($l != "") and (not ($l | str starts-with "#")) and ($l | str contains "=")) }
            | filter { |line| let var_value = ($line | split row "=" | skip 1 | str join "=" | str trim); (($var_value | str starts-with "op://") and (($line | split row "=" | first | str trim) in $env_keys)) }
            | each { |line| $line | split row "=" | first | str trim })
    } catch { [] }

    $conflicts
}

def main [] {
    let input = try { open --raw /dev/stdin | from json } catch { exit 0 }

    if ($input | get -i tool_name | default "") != "Bash" { exit 0 }

    let command = $input | get -i tool_input.command | default ""
    if $command == "" { exit 0 }
    if not ($command | str contains "op run") { exit 0 }

    let conflicts = try {
        let direct = (find_direct_env_conflicts)
        let file = (find_env_file_conflicts $command)
        ($direct ++ $file) | uniq
    } catch { [] }

    if ($conflicts | is-empty) { exit 0 }

    let unset_flags = ($conflicts | sort | each { |v| $"-u ($v)" } | str join " ")
    let corrected = $"env ($unset_flags) ($command)"
    let var_list = ($conflicts | sort | str join ", ")
    let n = $conflicts | length

    let message = ([
        $"[op-conflict-resolver] Found ($n) environment var(s) that conflict with op:// resolution: ($var_list)"
        ""
        "These vars are already set in shell and will block op run from injecting the 1Password values."
        ""
        "Corrected command:"
        $corrected
        ""
        "Re-run with the corrected command above."
    ] | str join "\n")

    deny $message
}
