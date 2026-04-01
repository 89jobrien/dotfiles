#!/usr/bin/env nu
# post-nextest-snap-notify.nu — PostToolUse hook (Bash)
# After a successful cargo nextest run, checks for pending .snap.new files.

def main [] {
    let input = open --raw /dev/stdin | from json
    let cmd = $input | get -i tool_input.command | default ""
    let exit_code = $input | get -i tool_response.exit_code | default 1

    if not ($cmd | str contains "cargo nextest") { exit 0 }
    if $exit_code != 0 { exit 0 }

    # Find .snap.new files (exclude target/)
    let snap_files = (
        do { ^fd --extension snap.new --exclude target } | complete
        | get stdout
        | lines
        | where { |l| $l != "" }
    )

    if ($snap_files | is-empty) { exit 0 }

    let count = $snap_files | length

    print ""
    print $"📸 ($count) snapshot update\(s\) pending after nextest:"
    $snap_files | each { |f| print $"  ($f)" }
    print ""
    print "Review with: rust-snapshot-review skill"
    print "Quick accept: for f in $(find . -name '*.snap.new' -not -path '*/target/*'); do mv \"$f\" \"${f%.new}\"; done"
}
