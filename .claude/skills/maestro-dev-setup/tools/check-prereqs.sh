#!/usr/bin/env bash
# Check all Maestro development prerequisites and report status.
# Usage: ./check-prereqs.sh [--install]
#   --install  Attempt to install missing tools via Homebrew/cargo

set -euo pipefail

INSTALL=false
[[ "${1:-}" == "--install" ]] && INSTALL=true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() { printf "${GREEN}✓${NC} %-20s %s\n" "$1" "$2"; }
fail() { printf "${RED}✗${NC} %-20s %s\n" "$1" "$2"; }
warn() { printf "${YELLOW}!${NC} %-20s %s\n" "$1" "$2"; }

MISSING=()

check_tool() {
    local name="$1" cmd="$2" install_cmd="${3:-}"
    if eval "$cmd" &>/dev/null; then
        local version
        version=$(eval "$cmd" 2>&1 | head -1)
        pass "$name" "$version"
    else
        fail "$name" "not found"
        [[ -n "$install_cmd" ]] && MISSING+=("$install_cmd")
    fi
}

echo "=== Maestro Dev Prerequisites ==="
echo ""

check_tool "Rust" "rustc --version" ""
check_tool "Cargo" "cargo --version" ""
check_tool "Docker" "command docker --version" "brew install colima docker"
check_tool "kubectl" "kubectl version --client 2>&1" "brew install kubectl"
check_tool "gcloud" "gcloud --version" "brew install --cask google-cloud-sdk"
check_tool "Helm" "helm version --short" "brew install helm"
check_tool "gh" "gh --version" "brew install gh"
check_tool "Node.js" "node --version" "brew install node"
check_tool "jq" "jq --version" "brew install jq"
check_tool "cargo-nextest" "cargo nextest --version" "cargo install cargo-nextest --locked"
check_tool "cargo-watch" "cargo watch --version" "cargo install cargo-watch"

echo ""
echo "=== Runtime Services ==="
echo ""

# Docker daemon
if command docker info &>/dev/null 2>&1; then
    pass "Docker daemon" "running"
else
    if command -v colima &>/dev/null; then
        warn "Docker daemon" "not running (try: colima start)"
    else
        fail "Docker daemon" "not running"
    fi
fi

# kubectl context
CONTEXT=$(kubectl config current-context 2>/dev/null || true)
if [[ "$CONTEXT" == "gke_toptal-maestro_us-east1_main-0" ]]; then
    pass "kubectl context" "$CONTEXT"
elif [[ -n "$CONTEXT" ]]; then
    warn "kubectl context" "$CONTEXT (expected gke_toptal-maestro_us-east1_main-0)"
else
    fail "kubectl context" "not set"
fi

# Maestro CLI
if command -v maestro &>/dev/null || [[ -x "$HOME/dev/maestro/target/release/maestro" ]]; then
    MAESTRO_BIN=$(command -v maestro 2>/dev/null || echo "$HOME/dev/maestro/target/release/maestro")
    pass "Maestro CLI" "$($MAESTRO_BIN --version 2>&1)"
    # Auth status
    AUTH=$($MAESTRO_BIN auth status 2>&1 | head -1 || true)
    if echo "$AUTH" | grep -q "Authenticated"; then
        pass "Maestro auth" "$AUTH"
    else
        warn "Maestro auth" "not authenticated (run: maestro auth login)"
    fi
else
    fail "Maestro CLI" "not built (run: make build)"
fi

echo ""

# Summary
if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "=== Missing Tools ==="
    echo ""
    for cmd in "${MISSING[@]}"; do
        echo "  $cmd"
    done
    echo ""
    if $INSTALL; then
        echo "Installing missing tools..."
        for cmd in "${MISSING[@]}"; do
            echo "  Running: $cmd"
            eval "$cmd"
        done
        echo ""
        echo "Done. Re-run without --install to verify."
    else
        echo "Run with --install to install missing tools automatically."
    fi
else
    echo "All prerequisites satisfied."
fi
