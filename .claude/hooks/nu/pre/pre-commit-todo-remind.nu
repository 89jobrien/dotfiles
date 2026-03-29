#!/usr/bin/env nu
# pre-commit-todo-remind.nu — PreToolUse hook (Bash)
# Before git commit, checks for in-progress doob todos and reminds to
# include "closes <uuid>" in the commit message for auto-completion.

def main [] {
    let input = open --raw /dev/stdin | from json
    let cmd = $input | get -i tool_input.command | default ""

    if not ($cmd | str contains "git commit") { exit 0 }
    if (which doob | is-empty) { exit 0 }

    # Skip if commit message already contains closes/fixes/resolves
    if ($cmd =~ '(?i)(closes?|fixes?|resolves?) [0-9a-f]{8}-') { exit 0 }

    # Get in-progress todos
    let result = (do { ^doob todo list } | complete)
    if $result.exit_code != 0 { exit 0 }

    let uuid_pat = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    let in_progress = ($result.stdout
        | lines
        | where { |l| ($l | str downcase | str contains "in_progress") or ($l | str downcase | str contains "in-progress") or ($l | str downcase | str contains "started") }
        | first 5)

    if ($in_progress | is-empty) { exit 0 }

    print ""
    print "📋 In-progress todos (add 'closes <uuid>' to auto-complete):"
    for line in $in_progress {
        let parsed = ($line | parse --regex $uuid_pat)
        if not ($parsed | is-empty) {
            let uuid = $parsed | first | values | first
            let desc = ($line | str replace $uuid "" | str trim | str substring 0..60)
            print $"  ($uuid)  ($desc)"
        }
    }
}
