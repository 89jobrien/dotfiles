#!/usr/bin/env nu
# post-edit-cargo-fmt.nu — PostToolUse hook
# Runs `cargo fmt --all` on the workspace when a .rs file is edited.

def main [] {
    let input = open --raw /dev/stdin | from json
    let file_path = $input | get -i tool_input.file_path | default ""

    if not ($file_path | str ends-with ".rs") { exit 0 }

    # Walk up from the file to find the workspace root
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

    let root = $workspace_root
    if $root == "" { exit 0 }

    # Run cargo fmt (non-blocking — don't fail if fmt errors)
    do { cd $root; ^cargo fmt --all } | ignore
}
