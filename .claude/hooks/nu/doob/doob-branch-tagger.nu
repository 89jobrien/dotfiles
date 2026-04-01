#!/usr/bin/env nu
# doob-branch-tagger.nu — PreToolUse hook
# Rewrites `doob todo add <text>` to inject --tags <branch> when on a feature/fix/chore branch.
# Only triggers if the command doesn't already contain --tags.

def main [] {
    let input = open --raw /dev/stdin | from json
    let cmd = $input | get -i tool_input.command | default ""

    if $cmd == "" { exit 0 }
    if not ($cmd | str contains "doob todo add") { exit 0 }
    if ($cmd | str contains "--tags") { exit 0 }

    let branch_result = (do { ^git rev-parse --abbrev-ref HEAD } | complete)
    if $branch_result.exit_code != 0 { exit 0 }
    let branch = $branch_result.stdout | str trim

    if not ($branch =~ '^(feature|fix|chore|feat)/') { exit 0 }

    # Extract slug: strip prefix, replace / and _ with -
    let slug = ($branch
        | str replace --regex '^[^/]*/' ''
        | str replace --all '/' '-'
        | str replace --all '_' '-'
        | str downcase)

    let new_cmd = $"($cmd) --tags ($slug)"
    let updated_input = ($input.tool_input | upsert command $new_cmd)

    {
        hookSpecificOutput: {
            hookEventName: "PreToolUse"
            permissionDecision: "allow"
            permissionDecisionReason: "doob-branch-tagger: injected --tags from branch"
            updatedInput: $updated_input
        }
    } | to json | print
}
