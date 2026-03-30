#!/usr/bin/env nu
# post-bash-redact.nu — PostToolUse hook
# Detects and redacts secrets in bash tool output using the `redact` utility.

def main [] {
    let input = $in | from json

    let resp = $input | get -i tool_response | default {}
    let output = ($resp | get -i stdout | default "") + ($resp | get -i output | default "")

    if $output == "" {
        {decision: "allow"} | to json | print
        exit 0
    }

    # Check if redact changes anything (secrets present)
    let redact_result = (do { echo $output | ^redact --level minimal } | complete)
    let redacted = if $redact_result.exit_code == 0 { $redact_result.stdout } else { $output }

    if $output == $redacted {
        {decision: "allow"} | to json | print
        exit 0
    }

    # Secrets found — emit redacted output as a message to Claude
    let msg = $"[redact] Output contained secrets — redacted version:\n\n($redacted)"
    {decision: "allow", message: $msg} | to json | print
}
