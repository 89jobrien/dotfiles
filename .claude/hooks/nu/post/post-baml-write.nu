#!/usr/bin/env nu
# post-baml-write.nu — PostToolUse hook (Edit|Write)
# After editing a .baml file, runs cargo check -p devloop-baml to catch schema errors early.

def main [] {
    let input = open --raw /dev/stdin | from json
    let file_path = $input | get -i tool_input.file_path | default ""

    if not ($file_path | str ends-with ".baml") { exit 0 }

    # Walk up from the file to find the workspace root (Cargo.toml with [workspace])
    let search_dir = $file_path | path dirname
    mut dir = $search_dir
    mut workspace_root = ""
    loop {
        let cargo = $dir | path join "Cargo.toml"
        if ($cargo | path exists) {
            let contents = open $cargo
            if ($contents | str contains "[workspace]") {
                $workspace_root = $dir
                break
            }
        }
        let parent = $dir | path dirname
        if $parent == $dir { break }
        $dir = $parent
    }

    let root = $workspace_root
    if $root == "" { exit 0 }

    let baml_crate = $root | path join "crates" "baml"
    if not ($baml_crate | path exists) { exit 0 }

    # Run cargo check quietly — only surface errors
    let result = (do { cd $root; ^cargo check -p devloop-baml } | complete)
    let errors = ($result.stderr | lines | where { |l| $l | str starts-with "error" } | first 5)

    if not ($errors | is-empty) {
        let basename = $file_path | path basename
        print ""
        print $"⚠ BAML compile check failed after editing ($basename):"
        $errors | each { |e| print $e }
        print "Fix schema errors before running devloop analyze."
    }
}
