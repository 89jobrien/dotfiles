#!/usr/bin/env nu
# mbx-gate — smart quality gate runner for minibox (nushell)
# Usage: mbx-gate [--full | --quick | --auto]

def ok [msg: string] { print $"  (ansi green)✓(ansi reset)  ($msg)" }
def skip [msg: string] { print $"  (ansi grey)⊘  ($msg)(ansi reset)" }
def step [msg: string] { print $"\n  (ansi cyan_bold)▸(ansi reset)  (ansi attr_bold)($msg)(ansi reset)" }
def fail [msg: string] { print $"  (ansi yellow)✗(ansi reset)  ($msg)" }

def main [
    --full    # Run full test suite including property tests and integration (if Linux+root)
    --quick   # Unit tests only, skip property and integration
] {
    let mode = if $full { "--full" } else if $quick { "--quick" } else { "--auto" }
    let repo_root = (git rev-parse --show-toplevel | str trim)
    cd $repo_root

    # Gather changed files
    let changed = (do { git diff --name-only HEAD } | complete | get stdout | lines)
    let staged = (do { git diff --cached --name-only } | complete | get stdout | lines)
    let all_changed = ($changed | append $staged | uniq | where { |f| ($f | str trim) != "" })

    let has_rs = ($all_changed | any { |f| $f =~ '\.rs$' })
    let has_toml = ($all_changed | any { |f| $f =~ '(Cargo\.toml|deny\.toml)$' })
    let doc_only = ($all_changed | all { |f| $f =~ '\.(md|txt|toml)$' })
    let has_bench = ($all_changed | any { |f| $f =~ '(bench|criterion)' })

    if $mode == "--auto" {
        if ($all_changed | is-empty) {
            print "No changes detected. Nothing to gate."
            return
        }

        if $doc_only {
            step "docs-only changes — fmt check only"
            let r = (do { cargo fmt --all --check } | complete)
            if $r.exit_code == 0 { ok "fmt" } else { fail "fmt"; exit 1 }
            return
        }
    }

    # ── fmt ──
    step "format check"
    let fmt_r = (do { cargo fmt --all --check } | complete)
    if $fmt_r.exit_code == 0 {
        ok "cargo fmt"
    } else {
        fail "cargo fmt — run 'cargo fmt --all' to fix"
        exit 1
    }

    # ── clippy ──
    step "clippy lint"
    let clippy_r = (do {
        cargo clippy -p minibox-lib -p minibox-macros -p minibox-cli -p daemonbox -p macbox -p miniboxd -p minibox-llm -p minibox-secrets -- -D warnings
    } | complete)
    if $clippy_r.exit_code == 0 {
        ok "clippy"
    } else {
        print $clippy_r.stderr
        fail "clippy"
        exit 1
    }

    # ── tests ──
    match $mode {
        "--quick" => {
            step "quick test (unit only)"
            let r = (do { cargo xtask test-unit } | complete)
            if $r.exit_code == 0 { ok "test-unit" } else { fail "test-unit"; exit 1 }
        }
        "--full" => {
            step "full test suite"
            let r = (do { cargo xtask test-unit } | complete)
            if $r.exit_code == 0 { ok "test-unit" } else { fail "test-unit"; exit 1 }

            let r2 = (do { cargo xtask test-property } | complete)
            if $r2.exit_code == 0 { ok "test-property" } else { fail "test-property"; exit 1 }

            if (uname | get kernel-name) == "Linux" and (id -u | into int) == 0 {
                step "integration tests (Linux + root)"
                let r3 = (do { just test-integration } | complete)
                if $r3.exit_code == 0 { ok "integration" } else { fail "integration (non-fatal)" }
            } else {
                skip "integration tests (requires Linux + root)"
            }
        }
        _ => {
            if $has_rs or $has_toml {
                step "unit + conformance tests"
                let r = (do { cargo xtask test-unit } | complete)
                if $r.exit_code == 0 { ok "test-unit" } else { fail "test-unit"; exit 1 }

                if $has_bench {
                    step "benchmark sanity check"
                    let r2 = (do { cargo build --release -p minibox-bench } | complete)
                    if $r2.exit_code == 0 { ok "bench build" } else { fail "bench build" }
                }
            } else {
                skip "no Rust changes — skipping tests"
            }
        }
    }

    # ── build ──
    step "release build"
    do { cargo build --release -p minibox-lib -p minibox-macros -p minibox-cli -p daemonbox -p minibox-bench } | complete | ignore
    ok "release build"

    print ""
    ok "all gates passed"
}
