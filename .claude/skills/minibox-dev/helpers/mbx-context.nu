#!/usr/bin/env nu
# mbx-context — quick context loader for minibox (nushell)
# Usage: mbx-context [--brief | --full]

def hdr [title: string] { print $"\n  (ansi cyan_bold)── ($title) ──(ansi reset)\n" }

def main [
    --full    # Show adapter suites, domain traits, and plan status
] {
    let mode = if $full { "--full" } else { "--brief" }
    let repo_root = (git rev-parse --show-toplevel | str trim)
    cd $repo_root

    # ── Header ──
    let version = (open Cargo.toml | get workspace.package.version)
    let rust_ver = (rustc --version | split row " " | get 1)
    print $"(ansi cyan_bold)minibox(ansi reset) v($version) · (uname | get kernel-name) · rust ($rust_ver)"

    # ── Branch ──
    hdr "branch"
    let branch = (git branch --show-current | str trim)
    let commit = (git log -1 --format='%h %s (%cr)' | str trim)
    print $"  (ansi attr_bold)($branch)(ansi reset) · ($commit)"

    let dirty_files = (git status --porcelain | lines | where { |l| ($l | str trim) != "" })
    let dirty = ($dirty_files | length)
    if $dirty > 0 {
        print $"  (ansi yellow)($dirty) dirty files(ansi reset)"
        $dirty_files | first ([$dirty 10] | math min) | each { |l| print $"    ($l)" }
        if $dirty > 10 {
            print $"    (ansi grey)... and ($dirty - 10) more(ansi reset)"
        }
    }

    # ── Crate Layout ──
    hdr "crate layout"
    print "  crates/"
    let crate_dirs = (ls crates/ | where type == dir | get name | sort)

    for crate_dir in $crate_dirs {
        let name = ($crate_dir | path basename)
        let cargo_path = $"($crate_dir)/Cargo.toml"
        let is_bin = if ($cargo_path | path exists) {
            (open $cargo_path --raw) =~ '\\[\\[bin\\]\\]'
        } else { false }
        let kind = if $is_bin { "bin" } else { "lib" }

        let rs_files = (glob $"($crate_dir)/src/**/*.rs")
        let loc = if ($rs_files | is-empty) { 0 } else {
            $rs_files | each { |f| open $f --raw | lines | length } | math sum
        }

        print $"    ($name | fill -w 20) (ansi grey)($kind) · ($loc | into string | fill -a right -w 5) lines(ansi reset)"
    }
    print "  xtask/"
    print $"    ('xtask' | fill -w 20) (ansi grey)bin · dev tool(ansi reset)"

    # ── Recent Commits ──
    hdr "recent commits (7d)"
    let commits = (git log --oneline --since="7 days ago" --no-merges --format="%h %s (%cr)" | lines)
    $commits | first ([($commits | length) 15] | math min) | each { |c| print $"  ($c)" }
    if ($commits | length) > 15 {
        print $"  (ansi grey)... and (($commits | length) - 15) more(ansi reset)"
    }

    # ── Full mode ──
    if $mode == "--full" {
        hdr "adapter suites"
        print $"  (ansi green)●(ansi reset)  native    (ansi grey)Linux namespaces, overlay, cgroups v2(ansi reset)"
        print $"  (ansi green)●(ansi reset)  gke       (ansi grey)proot, copy FS, no-op limiter(ansi reset)"
        print $"  (ansi green)●(ansi reset)  colima    (ansi grey)macOS via limactl/nerdctl(ansi reset)"
        print $"  (ansi grey)○(ansi reset)  vf        (ansi grey)Virtualization.framework \(not wired\)(ansi reset)"
        print $"  (ansi grey)○(ansi reset)  wsl2      (ansi grey)WSL2 \(not wired\)(ansi reset)"
        print $"  (ansi grey)○(ansi reset)  hcs       (ansi grey)Windows HCS \(not wired\)(ansi reset)"

        hdr "domain traits"
        let trait_lines = (grep -n 'pub trait' crates/minibox-lib/src/domain.rs | lines)
        for line in $trait_lines {
            # Split only on first colon to avoid splitting on `: AsAny + Send + Sync`
            let colon_pos = ($line | str index-of ":")
            let line_no = ($line | str substring 0..$colon_pos)
            let rest = ($line | str substring ($colon_pos + 1)..)
            let trait_name = ($rest | str replace -r '.*pub trait ([A-Za-z]+).*' '$1')
            let impls = (do { grep -rl $"impl.*($trait_name)" crates/ } | complete | get stdout | lines | where { |l| ($l | str trim) != "" } | length)
            print $"  ($trait_name | fill -w 24) (ansi grey)L($line_no) · ($impls) impl\(s\)(ansi reset)"
        }

        hdr "plans + specs"
        let plan_files = (glob "docs/{plans,superpowers/specs,superpowers/plans}/*.md")
        for f in $plan_files {
            let fname = ($f | path basename)
            let header = (open $f --raw | lines | first 5 | str join "\n")
            let status = if ($header =~ '(?i)status:') {
                $header | lines | where { |l| $l =~ '(?i)status:' } | first | str replace -r '.*status:\s*' '' | str trim
            } else { "?" }
            let icon = if ($status =~ '(?i)(implemented|complete|done)') {
                $"(ansi green)✓(ansi reset)"
            } else if ($status =~ '(?i)(draft|proposed)') {
                $"(ansi yellow)◌(ansi reset)"
            } else if ($status =~ '(?i)(approved|ready)') {
                $"(ansi cyan)●(ansi reset)"
            } else {
                $"(ansi grey)?(ansi reset)"
            }
            print $"  ($icon)  ($fname | fill -w 50) (ansi grey)($status)(ansi reset)"
        }
    }

    print ""
}
