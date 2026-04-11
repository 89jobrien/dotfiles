#!/usr/bin/env bash
# mbx-gate — smart quality gate runner for minibox
# Picks the right gate based on what changed since last commit.
# Usage: mbx-gate [--full | --quick | --auto]
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
cd "$REPO_ROOT"

C='\033[36m'; B='\033[1m'; G='\033[32m'; Y='\033[33m'; R='\033[0m'; D='\033[2m'
ok()   { printf "  ${G}✓${R}  %s\n" "$1"; }
skip() { printf "  ${D}⊘  %s${R}\n" "$1"; }
step() { printf "\n  ${B}${C}▸${R}  ${B}%s${R}\n" "$1"; }
fail() { printf "  ${Y}✗${R}  %s\n" "$1"; }

MODE="${1:---auto}"

# Gather changed files (staged + unstaged vs HEAD)
CHANGED=$(git diff --name-only HEAD 2>/dev/null || true)
STAGED=$(git diff --cached --name-only 2>/dev/null || true)
ALL_CHANGED=$(printf '%s\n%s' "$CHANGED" "$STAGED" | sort -u | grep -v '^$' || true)

has_rs_changes()   { echo "$ALL_CHANGED" | grep -qE '\.rs$'; }
has_toml_changes() { echo "$ALL_CHANGED" | grep -qE '(Cargo\.toml|deny\.toml)$'; }
has_doc_only()     { ! echo "$ALL_CHANGED" | grep -qvE '\.(md|txt|toml)$'; }
has_bench_changes(){ echo "$ALL_CHANGED" | grep -qE '(bench|criterion)'; }

if [ "$MODE" = "--auto" ]; then
    if [ -z "$ALL_CHANGED" ]; then
        echo "No changes detected. Nothing to gate."
        exit 0
    fi

    if has_doc_only; then
        step "docs-only changes — fmt check only"
        cargo fmt --all --check && ok "fmt" || fail "fmt"
        exit $?
    fi
fi

# ── fmt ──
step "format check"
if cargo fmt --all --check 2>/dev/null; then
    ok "cargo fmt"
else
    fail "cargo fmt — run 'cargo fmt --all' to fix"
    exit 1
fi

# ── clippy ──
step "clippy lint"
CLIPPY_CRATES="-p minibox-lib -p minibox-macros -p minibox-cli -p daemonbox -p macbox -p miniboxd -p minibox-llm -p minibox-secrets"
if cargo clippy $CLIPPY_CRATES -- -D warnings 2>&1; then
    ok "clippy"
else
    fail "clippy"
    exit 1
fi

# ── tests ──
if [ "$MODE" = "--quick" ]; then
    step "quick test (unit only)"
    cargo xtask test-unit && ok "test-unit" || { fail "test-unit"; exit 1; }
elif [ "$MODE" = "--full" ]; then
    step "full test suite"
    cargo xtask test-unit && ok "test-unit" || { fail "test-unit"; exit 1; }
    cargo xtask test-property && ok "test-property" || { fail "test-property"; exit 1; }
    if [ "$(uname)" = "Linux" ] && [ "$(id -u)" = "0" ]; then
        step "integration tests (Linux + root)"
        just test-integration && ok "integration" || fail "integration (non-fatal)"
    else
        skip "integration tests (requires Linux + root)"
    fi
else
    # auto mode
    if has_rs_changes || has_toml_changes; then
        step "unit + conformance tests"
        cargo xtask test-unit && ok "test-unit" || { fail "test-unit"; exit 1; }

        if has_bench_changes; then
            step "benchmark sanity check"
            cargo build --release -p minibox-bench && ok "bench build" || fail "bench build"
        fi
    else
        skip "no Rust changes — skipping tests"
    fi
fi

# ── build ──
step "release build"
cargo build --release -p minibox-lib -p minibox-macros -p minibox-cli -p daemonbox -p minibox-bench 2>&1 \
    | grep -E '^(Compiling|Finished|error)' | tail -3
ok "release build"

echo ""
ok "all gates passed"
