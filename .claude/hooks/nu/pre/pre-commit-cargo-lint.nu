#!/usr/bin/env nu
# pre-commit-cargo-lint.nu — PreToolUse hook (Bash)
# On git commit commands in a Rust workspace, runs cargo fmt --check and
# cargo clippy and prints warnings to stderr. Never blocks. Always exits 0.

def find_workspace_root [start: string] {
    mut dir = $start
    loop {
        let cargo = $dir | path join "Cargo.toml"
        if ($cargo | path exists) {
            let contents = open $cargo
            if ($contents | str contains "[workspace]") {
                return $dir
            }
        }
        let parent = $dir | path dirname
        if $parent == $dir { return "" }
        $dir = $parent
    }
}

def main [] {
    let input = open --raw /dev/stdin | from json
    let cmd = $input | get -i tool_input.command | default ""

    # Only trigger on git commit commands
    if not ($cmd | str contains "git commit") { exit 0 }

    # Find the working directory from the command context, fall back to pwd
    let cwd = (do { ^pwd } | complete).stdout | str trim
    let root = find_workspace_root $cwd

    # Not a Rust workspace — nothing to check
    if $root == "" { exit 0 }

    # Run cargo fmt --check (non-blocking)
    let fmt_result = (do { cd $root; ^cargo fmt --all --check 2>&1 } | complete)
    if $fmt_result.exit_code != 0 {
        print --stderr $"[pre-commit] cargo fmt --check failed \(run `cargo fmt --all` to fix\):\n($fmt_result.stdout)"
    }

    # Run cargo clippy (non-blocking)
    let clippy_result = (do { cd $root; ^cargo clippy --all-targets 2>&1 } | complete)
    if $clippy_result.exit_code != 0 {
        print --stderr $"[pre-commit] cargo clippy warnings:\n($clippy_result.stdout)"
    }

    # Always allow the commit through
    exit 0
}
