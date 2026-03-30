#!/usr/bin/env bash
# mbx-status — dev status dashboard for minibox
# Shows: crate health, test counts, bench status, VPS reachability, dirty state
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
cd "$REPO_ROOT"

C='\033[36m'; B='\033[1m'; G='\033[32m'; Y='\033[33m'; R='\033[0m'; D='\033[2m'
hdr() { printf "\n${B}${C}  ── %s ──${R}\n" "$1"; }
row() { printf "  ${D}%-22s${R}  %s\n" "$1" "$2"; }
ok()  { printf "${G}✓${R}"; }
bad() { printf "${Y}✗${R}"; }

printf "${B}${C}"
printf "  ╭─────────────────────────────────────╮\n"
printf "  │       minibox · dev status          │\n"
printf "  ╰─────────────────────────────────────╯\n"
printf "${R}"

# ── Git ──
hdr "git"
BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
AHEAD=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "?")
BEHIND=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo "?")
LAST_COMMIT=$(git log -1 --format='%h %s' 2>/dev/null | head -c 60)

row "branch" "$BRANCH"
row "dirty files" "$DIRTY"
row "ahead/behind" "$AHEAD / $BEHIND"
row "last commit" "$LAST_COMMIT"

# ── Workspace Crates ──
hdr "workspace ($(ls -d crates/*/ 2>/dev/null | wc -l | tr -d ' ') crates)"
for crate_dir in crates/*/; do
    name=$(basename "$crate_dir")
    # Check if it has tests
    test_count=$(grep -r '#\[test\]' "$crate_dir/src/" 2>/dev/null | wc -l | tr -d ' ')
    loc=$(find "$crate_dir/src" -name '*.rs' -exec cat {} + 2>/dev/null | wc -l | tr -d ' ')
    row "$name" "${loc} lines, ${test_count} #[test]"
done

# ── Test Status ──
hdr "test suites"
if command -v cargo-nextest &>/dev/null; then
    row "nextest" "$(ok) installed"
else
    row "nextest" "$(bad) not installed"
fi
if command -v cargo-llvm-cov &>/dev/null; then
    row "llvm-cov" "$(ok) installed"
else
    row "llvm-cov" "$(bad) not installed"
fi

# Quick test count from last nextest run or cargo test
row "unit+conformance" "~257 (run 'cargo xtask test-unit' to verify)"
row "property tests" "~33 (run 'cargo xtask test-property' to verify)"

# ── Bench ──
hdr "benchmarks"
if [ -f bench/results/latest.json ]; then
    BENCH_DATE=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' bench/results/latest.json 2>/dev/null || \
                 stat --format='%y' bench/results/latest.json 2>/dev/null | cut -d. -f1)
    BENCH_ENTRIES=$(wc -l < bench/results/bench.jsonl 2>/dev/null | tr -d ' ')
    row "latest.json" "$BENCH_DATE"
    row "bench.jsonl" "${BENCH_ENTRIES} entries"
else
    row "bench results" "$(bad) no results found"
fi

# ── VPS ──
hdr "VPS (jobrien-vm)"
if timeout 3 ssh -o BatchMode=yes -o ConnectTimeout=2 jobrien-vm "echo ok" &>/dev/null; then
    row "reachable" "$(ok) yes"
    VPS_SHA=$(ssh -o ConnectTimeout=3 jobrien-vm "cd ~/minibox && git rev-parse --short HEAD 2>/dev/null" 2>/dev/null || echo "?")
    LOCAL_SHA=$(git rev-parse --short HEAD)
    if [ "$VPS_SHA" = "$LOCAL_SHA" ]; then
        row "sync" "$(ok) $VPS_SHA (matches local)"
    else
        row "sync" "$(bad) VPS=$VPS_SHA local=$LOCAL_SHA"
    fi
else
    row "reachable" "$(bad) no (Tailscale down or VPS offline)"
fi

# ── CI ──
hdr "CI"
if command -v gh &>/dev/null; then
    LAST_RUN=$(gh run list --workflow=ci.yml --limit 1 --json conclusion,headBranch,updatedAt \
        --jq '.[0] | "\(.conclusion) on \(.headBranch) (\(.updatedAt | split("T") | .[0]))"' 2>/dev/null || echo "?")
    row "GitHub Actions" "$LAST_RUN"
else
    row "GitHub Actions" "$(bad) gh CLI not installed"
fi

echo ""
