#!/usr/bin/env nu
# mbx-status — dev status dashboard for minibox (nushell)
# Shows: crate health, test counts, bench status, VPS reachability, dirty state

def hdr [title: string] { print $"\n  (ansi cyan_bold)── ($title) ──(ansi reset)" }
def row [label: string, value: string] { print $"  (ansi grey)($label | fill -w 22)(ansi reset)  ($value)" }

def main [] {
    let repo_root = (git rev-parse --show-toplevel | str trim)
    cd $repo_root

    print $"(ansi cyan_bold)"
    print "  ╭─────────────────────────────────────╮"
    print "  │       minibox · dev status          │"
    print "  ╰─────────────────────────────────────╯"
    print $"(ansi reset)"

    # ── Git ──
    hdr "git"
    let branch = (git branch --show-current | str trim)
    let dirty = (git status --porcelain | lines | length)
    let ahead = (do { git rev-list --count '@{u}..HEAD' } | complete | get stdout | str trim)
    let behind = (do { git rev-list --count 'HEAD..@{u}' } | complete | get stdout | str trim)
    let last_commit = (git log -1 --format='%h %s' | str trim | str substring 0..60)

    row "branch" $branch
    row "dirty files" $"($dirty)"
    row "ahead/behind" $"($ahead) / ($behind)"
    row "last commit" $last_commit

    # ── Workspace Crates ──
    let crate_dirs = (ls crates/ | where type == dir | get name)
    hdr $"workspace \(($crate_dirs | length) crates\)"

    for crate_dir in $crate_dirs {
        let name = ($crate_dir | path basename)
        let rs_files = (glob $"($crate_dir)/src/**/*.rs")
        let loc = if ($rs_files | is-empty) { 0 } else {
            $rs_files | each { |f| open $f --raw | lines | length } | math sum
        }
        let test_count = if ($rs_files | is-empty) { 0 } else {
            $rs_files | each { |f| open $f --raw | lines | where { |l| $l =~ '#\[test\]' } | length } | math sum
        }
        row $name $"($loc) lines, ($test_count) #[test]"
    }

    # ── Test Suites ──
    hdr "test suites"
    let has_nextest = (which cargo-nextest | is-not-empty)
    let has_llvm_cov = (which cargo-llvm-cov | is-not-empty)
    row "nextest" (if $has_nextest { $"(ansi green)✓(ansi reset) installed" } else { $"(ansi yellow)✗(ansi reset) not installed" })
    row "llvm-cov" (if $has_llvm_cov { $"(ansi green)✓(ansi reset) installed" } else { $"(ansi yellow)✗(ansi reset) not installed" })
    row "unit+conformance" "~257 (run 'cargo xtask test-unit' to verify)"
    row "property tests" "~33 (run 'cargo xtask test-property' to verify)"

    # ── Bench ──
    hdr "benchmarks"
    if ("bench/results/latest.json" | path exists) {
        let bench_mod = (ls bench/results/latest.json | get modified | first | format date "%Y-%m-%d %H:%M")
        let bench_entries = if ("bench/results/bench.jsonl" | path exists) {
            open bench/results/bench.jsonl --raw | lines | length
        } else { 0 }
        row "latest.json" $bench_mod
        row "bench.jsonl" $"($bench_entries) entries"
    } else {
        row "bench results" $"(ansi yellow)✗(ansi reset) no results found"
    }

    # ── VPS ──
    hdr "VPS (jobrien-vm)"
    let vps_check = (do { ssh -o BatchMode=yes -o ConnectTimeout=2 jobrien-vm "echo ok" } | complete)
    if $vps_check.exit_code == 0 {
        row "reachable" $"(ansi green)✓(ansi reset) yes"
        let vps_sha = (do { ssh -o ConnectTimeout=3 jobrien-vm "cd ~/minibox && git rev-parse --short HEAD" } | complete | get stdout | str trim)
        let local_sha = (git rev-parse --short HEAD | str trim)
        if $vps_sha == $local_sha {
            row "sync" $"(ansi green)✓(ansi reset) ($vps_sha) \(matches local\)"
        } else {
            row "sync" $"(ansi yellow)✗(ansi reset) VPS=($vps_sha) local=($local_sha)"
        }
    } else {
        row "reachable" $"(ansi yellow)✗(ansi reset) no \(Tailscale down or VPS offline\)"
    }

    # ── CI ──
    hdr "CI"
    let has_gh = (which gh | is-not-empty)
    if $has_gh {
        let last_run = (do { gh run list --workflow=ci.yml --limit 1 --json conclusion,headBranch,updatedAt --jq '.[0] | "\(.conclusion) on \(.headBranch) (\(.updatedAt | split("T") | .[0]))"' } | complete | get stdout | str trim)
        row "GitHub Actions" $last_run
    } else {
        row "GitHub Actions" $"(ansi yellow)✗(ansi reset) gh CLI not installed"
    }

    print ""
}
