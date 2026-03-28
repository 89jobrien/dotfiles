#!/usr/bin/env fish
# mbx-new-crate — scaffold a new workspace crate with all wiring (fish)
# Usage: mbx-new-crate <name> [--lib|--bin]

set REPO_ROOT (git rev-parse --show-toplevel 2>/dev/null; or echo $PWD)
cd $REPO_ROOT

function ok;   printf "  \033[32m✓\033[0m  %s\n" $argv; end
function step; printf "  \033[1m\033[36m▸\033[0m  \033[1m%s\033[0m\n" $argv; end
function warn; printf "  \033[33m!\033[0m  %s\n" $argv; end

set NAME $argv[1]
set KIND $argv[2]
test -z "$NAME"; and begin; echo "usage: mbx-new-crate <name> [--lib|--bin]"; exit 1; end
test -z "$KIND"; and set KIND "--lib"

# Validate name
if not string match -rq '^[a-z][a-z0-9_-]*$' -- $NAME
    echo "error: crate name must be lowercase alphanumeric with hyphens/underscores" >&2
    exit 1
end

set CRATE_DIR "crates/$NAME"

if test -d $CRATE_DIR
    echo "error: $CRATE_DIR already exists" >&2
    exit 1
end

step "creating crate: $NAME ($KIND)"
cargo new $CRATE_DIR $KIND
ok "cargo new"

step "adding license + workspace deps"
printf '[package]
name = "%s"
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
' $NAME > $CRATE_DIR/Cargo.toml
ok "Cargo.toml"

step "adding to workspace Cargo.toml"
if grep -q "\"crates/$NAME\"" Cargo.toml
    warn "already in workspace members"
else
    sed -i.bak "/\"xtask\"/i\\
    \"crates/$NAME\"," Cargo.toml; and rm -f Cargo.toml.bak
    ok "workspace member added"
end

step "verifying compilation"
if cargo check -p $NAME 2>&1 | tail -1
    ok "compiles"
else
    warn "check failed — may need manual fixes"
end

echo ""
printf "  \033[1m\033[36mremaining wiring:\033[0m\n"
echo "  1. Add -p $NAME to clippy in Justfile 'lint' recipe"
echo "  2. Add -p $NAME to .github/workflows/ci.yml clippy step"
echo "  3. Add to xtask test-unit + pre-commit crate lists"
echo "  4. Add crate description to CLAUDE.md + HANDOFF.md"
echo "  5. Run: cargo xtask pre-commit"
echo ""
ok "crate $NAME scaffolded at $CRATE_DIR"
