#!/usr/bin/env fish
# mbx-status — dev status dashboard for minibox (fish)
# Shows: crate health, test counts, bench status, VPS reachability, dirty state

set REPO_ROOT (git rev-parse --show-toplevel 2>/dev/null; or echo $PWD)
cd $REPO_ROOT

function hdr; printf "\n\033[1m\033[36m  ── %s ──\033[0m\n" $argv; end
function row; printf "  \033[2m%-22s\033[0m  %s\n" $argv[1] $argv[2]; end
function ok;  printf "\033[32m✓\033[0m"; end
function bad; printf "\033[33m✗\033[0m"; end

printf "\033[1m\033[36m"
printf "  ╭─────────────────────────────────────╮\n"
printf "  │       minibox · dev status          │\n"
printf "  ╰─────────────────────────────────────╯\n"
printf "\033[0m"

# ── Git ──
hdr "git"
set BRANCH (git branch --show-current 2>/dev/null; or echo "detached")
set DIRTY (git status --porcelain 2>/dev/null | wc -l | string trim)
set AHEAD (git rev-list --count '@{u}..HEAD' 2>/dev/null; or echo "?")
set BEHIND (git rev-list --count 'HEAD..@{u}' 2>/dev/null; or echo "?")
set LAST_COMMIT (git log -1 --format='%h %s' 2>/dev/null | string sub -l 60)

row "branch" "$BRANCH"
row "dirty files" "$DIRTY"
row "ahead/behind" "$AHEAD / $BEHIND"
row "last commit" "$LAST_COMMIT"

# ── Workspace Crates ──
set crate_count (ls -d crates/*/ 2>/dev/null | wc -l | string trim)
hdr "workspace ($crate_count crates)"
for crate_dir in crates/*/
    set name (basename $crate_dir)
    set test_count (grep -r '#\[test\]' $crate_dir/src/ 2>/dev/null | wc -l | string trim)
    set loc (find $crate_dir/src -name '*.rs' -exec cat '{}' + 2>/dev/null | wc -l | string trim)
    row "$name" "$loc lines, $test_count #[test]"
end

# ── Test Status ──
hdr "test suites"
if command -q cargo-nextest
    row "nextest" (printf "%s installed" (ok))
else
    row "nextest" (printf "%s not installed" (bad))
end
if command -q cargo-llvm-cov
    row "llvm-cov" (printf "%s installed" (ok))
else
    row "llvm-cov" (printf "%s not installed" (bad))
end
row "unit+conformance" "~257 (run 'cargo xtask test-unit' to verify)"
row "property tests" "~33 (run 'cargo xtask test-property' to verify)"

# ── Bench ──
hdr "benchmarks"
if test -f bench/results/latest.json
    set BENCH_DATE (stat -f '%Sm' -t '%Y-%m-%d %H:%M' bench/results/latest.json 2>/dev/null; or stat --format='%y' bench/results/latest.json 2>/dev/null | string split '.' | head -1)
    set BENCH_ENTRIES (wc -l < bench/results/bench.jsonl 2>/dev/null | string trim)
    row "latest.json" "$BENCH_DATE"
    row "bench.jsonl" "$BENCH_ENTRIES entries"
else
    row "bench results" (printf "%s no results found" (bad))
end

# ── VPS ──
hdr "VPS (jobrien-vm)"
if timeout 3 ssh -o BatchMode=yes -o ConnectTimeout=2 jobrien-vm "echo ok" &>/dev/null
    row "reachable" (printf "%s yes" (ok))
    set VPS_SHA (ssh -o ConnectTimeout=3 jobrien-vm "cd ~/minibox && git rev-parse --short HEAD 2>/dev/null" 2>/dev/null; or echo "?")
    set LOCAL_SHA (git rev-parse --short HEAD)
    if test "$VPS_SHA" = "$LOCAL_SHA"
        row "sync" (printf "%s %s (matches local)" (ok) $VPS_SHA)
    else
        row "sync" (printf "%s VPS=%s local=%s" (bad) $VPS_SHA $LOCAL_SHA)
    end
else
    row "reachable" (printf "%s no (Tailscale down or VPS offline)" (bad))
end

# ── CI ──
hdr "CI"
if command -q gh
    set LAST_RUN (gh run list --workflow=ci.yml --limit 1 --json conclusion,headBranch,updatedAt \
        --jq '.[0] | "\(.conclusion) on \(.headBranch) (\(.updatedAt | split("T") | .[0]))"' 2>/dev/null; or echo "?")
    row "GitHub Actions" "$LAST_RUN"
else
    row "GitHub Actions" (printf "%s gh CLI not installed" (bad))
end

echo ""
