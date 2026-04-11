#!/usr/bin/env nu
# post-edit-cargo-check.nu — PostToolUse hook
# Runs `cargo check --workspace` when a .rs file is edited.
# Surfaces errors to stderr but never blocks.

def find_workspace_root [file_path: string] {
    mut dir = ($file_path | path dirname)
    mut workspace_root = ""

    loop {
        let cargo = $dir | path join "Cargo.toml"
        if ($cargo | path exists) {
            let contents = open $cargo
            if ($contents | str contains "[workspace]") {
                $workspace_root = $dir
                break
            } else if $workspace_root == "" {
                $workspace_root = $dir
            }
        }
        let parent = $dir | path dirname
        if $parent == $dir { break }
        $dir = $parent
    }

    $workspace_root
}

def main [] {
    let input = open --raw /dev/stdin | from json
    let file_path = $input | get -i tool_input.file_path | default ""

    if not ($file_path | str ends-with ".rs") { exit 0 }

    let root = find_workspace_root $file_path
    if $root == "" { exit 0 }

    let result = (do { cd $root; ^cargo check --workspace 2>&1 } | complete)
    if $result.exit_code != 0 {
        print --stderr $"[post-edit] cargo check failed:\n($result.stdout)"
    }

    exit 0
}
