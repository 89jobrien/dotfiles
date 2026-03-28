#!/usr/bin/env fish
# mbx-gate — smart quality gate runner for minibox (fish)
# Usage: mbx-gate [--full | --quick | --auto]

set REPO_ROOT (git rev-parse --show-toplevel 2>/dev/null; or echo $PWD)
cd $REPO_ROOT

function ok;   printf "  \033[32m✓\033[0m  %s\n" $argv; end
function skip; printf "  \033[2m⊘  %s\033[0m\n" $argv; end
function step; printf "\n  \033[1m\033[36m▸\033[0m  \033[1m%s\033[0m\n" $argv; end
function fail; printf "  \033[33m✗\033[0m  %s\n" $argv; end

set MODE $argv[1]
test -z "$MODE"; and set MODE "--auto"

# Gather changed files
set ALL_CHANGED (begin; git diff --name-only HEAD 2>/dev/null; git diff --cached --name-only 2>/dev/null; end | sort -u | string match -rv '^$')

set -l has_rs 0
set -l has_toml 0
set -l has_non_doc 0
set -l has_bench 0

for f in $ALL_CHANGED
    string match -rq '\.rs$' -- $f; and set has_rs 1
    string match -rq '(Cargo\.toml|deny\.toml)$' -- $f; and set has_toml 1
    string match -rqv '\.(md|txt|toml)$' -- $f; and set has_non_doc 1
    string match -rq '(bench|criterion)' -- $f; and set has_bench 1
end

if test "$MODE" = "--auto"
    if test (count $ALL_CHANGED) -eq 0
        echo "No changes detected. Nothing to gate."
        exit 0
    end

    if test $has_non_doc -eq 0
        step "docs-only changes — fmt check only"
        cargo fmt --all --check; and ok "fmt"; or begin; fail "fmt"; exit 1; end
        exit 0
    end
end

# ── fmt ──
step "format check"
if cargo fmt --all --check 2>/dev/null
    ok "cargo fmt"
else
    fail "cargo fmt — run 'cargo fmt --all' to fix"
    exit 1
end

# ── clippy ──
step "clippy lint"
set CLIPPY_CRATES -p minibox-lib -p minibox-macros -p minibox-cli -p daemonbox -p macbox -p miniboxd -p minibox-llm -p minibox-secrets
if cargo clippy $CLIPPY_CRATES -- -D warnings 2>&1
    ok "clippy"
else
    fail "clippy"
    exit 1
end

# ── tests ──
switch $MODE
    case "--quick"
        step "quick test (unit only)"
        cargo xtask test-unit; and ok "test-unit"; or begin; fail "test-unit"; exit 1; end

    case "--full"
        step "full test suite"
        cargo xtask test-unit; and ok "test-unit"; or begin; fail "test-unit"; exit 1; end
        cargo xtask test-property; and ok "test-property"; or begin; fail "test-property"; exit 1; end
        if test (uname) = "Linux" -a (id -u) = "0"
            step "integration tests (Linux + root)"
            just test-integration; and ok "integration"; or fail "integration (non-fatal)"
        else
            skip "integration tests (requires Linux + root)"
        end

    case "*"
        # auto
        if test $has_rs -eq 1 -o $has_toml -eq 1
            step "unit + conformance tests"
            cargo xtask test-unit; and ok "test-unit"; or begin; fail "test-unit"; exit 1; end

            if test $has_bench -eq 1
                step "benchmark sanity check"
                cargo build --release -p minibox-bench; and ok "bench build"; or fail "bench build"
            end
        else
            skip "no Rust changes — skipping tests"
        end
end

# ── build ──
step "release build"
cargo build --release -p minibox-lib -p minibox-macros -p minibox-cli -p daemonbox -p minibox-bench 2>&1 \
    | grep -E '^(Compiling|Finished|error)' | tail -3
ok "release build"

echo ""
ok "all gates passed"
