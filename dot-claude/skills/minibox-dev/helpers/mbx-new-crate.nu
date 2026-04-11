#!/usr/bin/env nu
# mbx-new-crate — scaffold a new workspace crate with all wiring (nushell)
# Usage: mbx-new-crate <name> [--lib|--bin]

def ok [msg: string] { print $"  (ansi green)✓(ansi reset)  ($msg)" }
def step [msg: string] { print $"  (ansi cyan_bold)▸(ansi reset)  (ansi attr_bold)($msg)(ansi reset)" }
def warn [msg: string] { print $"  (ansi yellow)!(ansi reset)  ($msg)" }

def main [
    name: string     # Crate name (lowercase, hyphens/underscores)
    --bin            # Create binary crate instead of library
] {
    let kind = if $bin { "--bin" } else { "--lib" }
    let repo_root = (git rev-parse --show-toplevel | str trim)
    cd $repo_root

    # Validate name
    if not ($name =~ '^[a-z][a-z0-9_-]*$') {
        print $"error: crate name must be lowercase alphanumeric with hyphens/underscores"
        exit 1
    }

    let crate_dir = $"crates/($name)"

    if ($crate_dir | path exists) {
        print $"error: ($crate_dir) already exists"
        exit 1
    }

    step $"creating crate: ($name) \(($kind)\)"
    cargo new $crate_dir $kind
    ok "cargo new"

    step "adding license + workspace deps"
    let cargo_toml = $'[package]
name = "($name)"
version.workspace = true
edition.workspace = true
license.workspace = true
rust-version.workspace = true

[dependencies]
anyhow.workspace = true
thiserror.workspace = true
tracing.workspace = true
serde.workspace = true
serde_json.workspace = true

[dev-dependencies]
tempfile.workspace = true
'
    $cargo_toml | save --force $"($crate_dir)/Cargo.toml"
    ok "Cargo.toml"

    step "adding to workspace Cargo.toml"
    let ws_toml = (open Cargo.toml --raw)
    if ($ws_toml | str contains $'"crates/($name)"') {
        warn "already in workspace members"
    } else {
        let updated = ($ws_toml | str replace '"xtask",' $'"crates/($name)",\n    "xtask",')
        $updated | save --force Cargo.toml
        ok "workspace member added"
    }

    step "verifying compilation"
    let r = (do { cargo check -p $name } | complete)
    if $r.exit_code == 0 {
        ok "compiles"
    } else {
        warn "check failed — may need manual fixes"
    }

    print ""
    print $"  (ansi cyan_bold)remaining wiring:(ansi reset)"
    print $"  1. Add -p ($name) to clippy in Justfile 'lint' recipe"
    print $"  2. Add -p ($name) to .github/workflows/ci.yml clippy step"
    print $"  3. Add to xtask test-unit + pre-commit crate lists"
    print $"  4. Add crate description to CLAUDE.md + HANDOFF.md"
    print "  5. Run: cargo xtask pre-commit"
    print ""
    ok $"crate ($name) scaffolded at ($crate_dir)"
}
