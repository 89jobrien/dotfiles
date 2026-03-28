#!/usr/bin/env nu
# pre-nextest-op-wrap.nu — PreToolUse hook (Bash)
# Rewrites `cargo nextest` commands to prepend _DEVLOOP_OP_WRAPPED=1
# if not already present. Prevents 1Password prompts during test runs.

def main [] {
    let input = $in | from json
    let cmd = $input | get -i tool_input.command | default ""

    if not ($cmd | str contains "cargo nextest") { exit 0 }
    if ($cmd | str contains "_DEVLOOP_OP_WRAPPED") { exit 0 }

    # Check if we're in a devloop-family project (has crates/ directory)
    let cwd = $env.PWD
    let has_crates = ($cwd | path join "crates" | path exists)
    if not $has_crates {
        if not ($cmd =~ '(^|/)devloop(/|$)') { exit 0 }
    }

    let new_cmd = $"_DEVLOOP_OP_WRAPPED=1 ($cmd)"
    let updated_input = ($input.tool_input | upsert command $new_cmd)

    {
        hookSpecificOutput: {
            hookEventName: "PreToolUse"
            permissionDecision: "allow"
            permissionDecisionReason: "pre-nextest-op-wrap: injected _DEVLOOP_OP_WRAPPED=1"
            updatedInput: $updated_input
        }
    } | to json | print
}
