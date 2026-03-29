#!/usr/bin/env nu
# doob-commit-autocomplete.nu — PostToolUse hook (Bash)
# After a git commit, reads the commit message and checks for
# "closes <uuid>", "fixes <uuid>", "resolves <uuid>" patterns, then marks
# matching doob todos as completed.

def main [] {
    let input = open --raw /dev/stdin | from json
    let cmd = $input | get -i tool_input.command | default ""
    let exit_code = $input | get -i exit_code | default ""

    if not ($cmd | str contains "git commit") { exit 0 }
    if $exit_code != "0" { exit 0 }

    let msg_result = (do { ^git log -1 --format=%B } | complete)
    if $msg_result.exit_code != 0 { exit 0 }
    let msg = $msg_result.stdout | str trim
    if $msg == "" { exit 0 }

    let uuid_pat = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    # Find UUIDs preceded by closes/fixes/resolves (case-insensitive)
    let uuids = ($msg | lines | each { |line|
        $line | parse --regex $'(?i)(closes?|fixes?|resolves?) +($uuid_pat)'
        | get -i capture2
        | default []
    } | flatten | uniq)

    if ($uuids | is-empty) { exit 0 }

    let log_file = "/tmp/doob-commit-autocomplete.log"

    # Log rotation: truncate to last 500 lines if file exceeds 1000 lines
    if ($log_file | path exists) {
        let lines = (open $log_file | lines | length)
        if $lines > 1000 {
            open $log_file | lines | last 500 | str join "\n" | save --force $log_file
        }
    }

    for uuid in $uuids {
        let result = (do { ^doob todo complete $uuid } | complete)
        let ts = (date now | format date "%Y-%m-%d %H:%M:%S")
        if $result.exit_code == 0 {
            $"[($ts)] Completed todo ($uuid) from commit\n" | save --append $log_file
        } else {
            $"[($ts)] Could not complete todo ($uuid) \(not found or already complete\)\n" | save --append $log_file
        }
    }
}
