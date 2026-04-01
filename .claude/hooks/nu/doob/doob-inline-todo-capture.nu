#!/usr/bin/env nu
# doob-inline-todo-capture.nu — PostToolUse hook (Edit|Write)
# After editing source files, scans newly added lines for TODO/FIXME comments
# and creates matching doob todos linked to the file.
# Supported: .rs .ts .js .go (// prefix), .py .sh (# prefix), .sql (-- prefix)

def main [] {
    let input = open --raw /dev/stdin | from json
    let tool = $input | get -i tool_name | default ""
    let file_path = $input | get -i tool_input.file_path | default ""

    if $file_path == "" { exit 0 }

    # Determine comment style based on file extension
    let comment_style = if ($file_path =~ '\.(rs|ts|js|go)$') {
        "slash"
    } else if ($file_path =~ '\.(py|sh)$') {
        "hash"
    } else if ($file_path =~ '\.sql$') {
        "dash"
    } else {
        exit 0
    }

    # Get newly added content
    let new_content = if $tool == "Edit" {
        $input | get -i tool_input.new_string | default ""
    } else if $tool == "Write" {
        $input | get -i tool_input.content | default ""
    } else {
        exit 0
    }

    if $new_content == "" { exit 0 }

    let log_file = "/tmp/doob-inline-todos.log"

    # Log rotation
    if ($log_file | path exists) {
        let line_count = (open $log_file | lines | length)
        if $line_count > 1000 {
            open $log_file | lines | last 500 | str join "\n" | save --force $log_file
        }
    }

    # Build pattern for the comment style
    let grep_pat = match $comment_style {
        "slash" => '//\s*(TODO|FIXME):\s*(.+)'
        "hash"  => '#\s*(TODO|FIXME):\s*(.+)'
        "dash"  => '--\s*(TODO|FIXME):\s*(.+)'
        _       => ""
    }
    if $grep_pat == "" { exit 0 }

    # Extract TODO/FIXME lines
    let todo_lines = ($new_content | lines | where { |line| $line =~ $grep_pat })

    for line in $todo_lines {
        let parsed = ($line | parse --regex $grep_pat)
        if ($parsed | is-empty) { continue }

        let marker = try { $parsed | get capture1 | first } catch { "" }
        let text = try { ($parsed | get capture2 | first | str trim) } catch { "" }

        if $marker == "" or $text == "" { continue }

        let tag = if $marker == "FIXME" { "inline-fixme" } else { "inline-todo" }

        let result = (do { ^doob todo add $text --file $file_path --tags $tag } | complete)
        if $result.exit_code == 0 {
            let ts = (date now | format date "%Y-%m-%d %H:%M:%S")
            $"[($ts)] Created todo from ($marker) in ($file_path): ($text)\n" | save --append $log_file
        }
    }
}
