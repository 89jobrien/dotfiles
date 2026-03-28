#!/usr/bin/env bash
# mbx-new-crate — scaffold a new workspace crate with all wiring
# Usage: mbx-new-crate <name> [--lib|--bin]
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
cd "$REPO_ROOT"

C='\033[36m'; B='\033[1m'; G='\033[32m'; Y='\033[33m'; R='\033[0m'
ok()   { printf "  ${G}✓${R}  %s\n" "$1"; }
step() { printf "  ${B}${C}▸${R}  ${B}%s${R}\n" "$1"; }
warn() { printf "  ${Y}!${R}  %s\n" "$1"; }

NAME="${1:?usage: mbx-new-crate <name> [--lib|--bin]}"
KIND="${2:---lib}"

# Validate name
if [[ ! "$NAME" =~ ^[a-z][a-z0-9_-]*$ ]]; then
    echo "error: crate name must be lowercase alphanumeric with hyphens/underscores" >&2
    exit 1
fi

CRATE_DIR="crates/$NAME"

if [ -d "$CRATE_DIR" ]; then
    echo "error: $CRATE_DIR already exists" >&2
    exit 1
fi

step "creating crate: $NAME ($KIND)"
cargo new "$CRATE_DIR" "$KIND"
ok "cargo new"

# Ensure license field (deny.toml requires it)
step "adding license + workspace deps"
cat > "$CRATE_DIR/Cargo.toml" <<TOML
[package]
name = "$NAME"
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
TOML
ok "Cargo.toml"

# Add to workspace members
step "adding to workspace Cargo.toml"
if grep -q "\"crates/$NAME\"" Cargo.toml; then
    warn "already in workspace members"
else
    # Insert before the closing bracket of members array
    sed -i.bak "/\"xtask\"/i\\
    \"crates/$NAME\",
" Cargo.toml && rm -f Cargo.toml.bak
    ok "workspace member added"
fi

# Verify it compiles
step "verifying compilation"
if cargo check -p "$NAME" 2>&1 | tail -1; then
    ok "compiles"
else
    warn "check failed — may need manual fixes"
fi

# Print wiring reminders
echo ""
printf "  ${B}${C}remaining wiring:${R}\n"
echo "  1. Add -p $NAME to clippy in Justfile 'lint' recipe"
echo "  2. Add -p $NAME to .github/workflows/ci.yml clippy step"
echo "  3. Add to xtask test-unit + pre-commit crate lists"
echo "  4. Add crate description to CLAUDE.md + HANDOFF.md"
echo "  5. Run: cargo xtask pre-commit"
echo ""
ok "crate $NAME scaffolded at $CRATE_DIR"
