#!/usr/bin/env nu
# rtk-hook-version: 2
# rtk-rewrite.nu — PreToolUse hook
# Rewrites commands to use rtk for token savings.
# All rewrite logic lives in `rtk rewrite` (src/discover/registry.rs).

def main [] {
    if (which rtk | is-empty) {
        print --stderr "[rtk] WARNING: rtk is not installed or not in PATH. Hook cannot rewrite commands."
        exit 0
    }

    # Version guard: rtk rewrite was added in 0.23.0
    let version_result = (do { ^rtk --version } | complete)
    if $version_result.exit_code == 0 {
        let version_str = ($version_result.stdout | parse --regex '(\d+)\.(\d+)\.(\d+)')
        if not ($version_str | is-empty) {
            let major = $version_str | first | get capture1 | into int
            let minor = $version_str | first | get capture2 | into int
            if $major == 0 and $minor < 23 {
                print --stderr $"[rtk] WARNING: rtk is too old \(need >= 0.23.0\). Upgrade: cargo install rtk"
                exit 0
            }
        }
    }

    let input = open --raw /dev/stdin | from json
    let cmd = $input | get -i tool_input.command | default ""

    if $cmd == "" { exit 0 }

    # Delegate all rewrite logic to the Rust binary
    let rewrite_result = (do { ^rtk rewrite $cmd } | complete)
    if $rewrite_result.exit_code != 0 { exit 0 }

    let rewritten = $rewrite_result.stdout | str trim
    if $cmd == $rewritten { exit 0 }

    let updated_input = ($input.tool_input | upsert command $rewritten)

    {
        hookSpecificOutput: {
            hookEventName: "PreToolUse"
            permissionDecision: "allow"
            permissionDecisionReason: "RTK auto-rewrite"
            updatedInput: $updated_input
        }
    } | to json | print
}
