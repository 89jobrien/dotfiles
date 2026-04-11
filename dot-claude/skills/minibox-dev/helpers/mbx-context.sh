#!/usr/bin/env bash
# mbx-context — quick context loader for minibox
# Prints crate layout, recent commits, branch state, and test status
# Usage: mbx-context [--brief | --full]
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
cd "$REPO_ROOT"

C='\033[36m'; B='\033[1m'; G='\033[32m'; Y='\033[33m'; R='\033[0m'; D='\033[2m'
hdr() { printf "\n${B}${C}  ── %s ──${R}\n\n" "$1"; }

MODE="${1:---brief}"

# ── Header ──
VERSION=$(grep '^version' Cargo.toml | head -1 | sed 's/.*"\(.*\)"/\1/')
printf "${B}${C}minibox${R} v${VERSION} · $(uname -s) · rust $(rustc --version 2>/dev/null | awk '{print $2}')${R}\n"

# ── Branch + State ──
hdr "branch"
BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
COMMIT=$(git log -1 --format='%h %s (%cr)' 2>/dev/null)
printf "  ${B}%s${R} · %s\n" "$BRANCH" "$COMMIT"

DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$DIRTY" -gt 0 ]; then
    printf "  ${Y}%s dirty files${R}\n" "$DIRTY"
    git status --porcelain 2>/dev/null | head -10 | sed 's/^/    /'
    [ "$DIRTY" -gt 10 ] && printf "    ${D}... and %d more${R}\n" "$((DIRTY - 10))"
fi

# ── Crate Layout ──
hdr "crate layout"
printf "  ${D}crates/${R}\n"
for crate_dir in crates/*/; do
    name=$(basename "$crate_dir")
    # Get crate type from Cargo.toml
    if grep -q '^\[lib\]' "$crate_dir/Cargo.toml" 2>/dev/null || \
       ! grep -q '^\[\[bin\]\]' "$crate_dir/Cargo.toml" 2>/dev/null; then
        kind="lib"
    else
        kind="bin"
    fi
    loc=$(find "$crate_dir/src" -name '*.rs' -exec cat {} + 2>/dev/null | wc -l | tr -d ' ')
    deps=$(grep -cE '^\w.*=.*\{|^\w.*=.*"' "$crate_dir/Cargo.toml" 2>/dev/null || echo 0)
    printf "    %-20s ${D}%s · %5s lines · %2s deps${R}\n" "$name" "$kind" "$loc" "$deps"
done
printf "  ${D}xtask/${R}\n"
printf "    %-20s ${D}bin · dev tool${R}\n" "xtask"

# ── Recent Commits ──
hdr "recent commits (7d)"
git log --oneline --since="7 days ago" --no-merges --format="  %C(auto)%h%C(reset) %s %C(dim)(%cr)%C(reset)" 2>/dev/null | head -15

TOTAL_7D=$(git log --oneline --since="7 days ago" --no-merges 2>/dev/null | wc -l | tr -d ' ')
[ "$TOTAL_7D" -gt 15 ] && printf "  ${D}... and %d more${R}\n" "$((TOTAL_7D - 15))"

# ── Full mode extras ──
if [ "$MODE" = "--full" ]; then
    # Adapter status
    hdr "adapter suites"
    printf "  ${G}●${R}  native    ${D}Linux namespaces, overlay, cgroups v2${R}\n"
    printf "  ${G}●${R}  gke       ${D}proot, copy FS, no-op limiter${R}\n"
    printf "  ${G}●${R}  colima    ${D}macOS via limactl/nerdctl${R}\n"
    printf "  ${D}○${R}  vf        ${D}Virtualization.framework (not wired)${R}\n"
    printf "  ${D}○${R}  wsl2      ${D}WSL2 (not wired)${R}\n"
    printf "  ${D}○${R}  hcs       ${D}Windows HCS (not wired)${R}\n"

    # Domain traits
    hdr "domain traits"
    grep -n 'pub trait' crates/minibox-lib/src/domain.rs 2>/dev/null | while read -r line; do
        trait_name=$(echo "$line" | sed 's/.*pub trait \([A-Za-z]*\).*/\1/')
        line_no=$(echo "$line" | cut -d: -f1)
        impls=$(grep -rl "impl.*$trait_name" crates/ 2>/dev/null | wc -l | tr -d ' ')
        printf "  %-24s ${D}L%s · %s impl(s)${R}\n" "$trait_name" "$line_no" "$impls"
    done

    # Open plans
    hdr "plans + specs"
    for f in docs/plans/*.md docs/superpowers/specs/*.md docs/superpowers/plans/*.md; do
        [ -f "$f" ] || continue
        status=$(head -5 "$f" | grep -i 'status:' | sed 's/.*status: *//' | tr -d '\r')
        fname=$(basename "$f")
        case "$status" in
            *implemented*|*complete*|*done*) icon="${G}✓${R}" ;;
            *draft*|*proposed*)              icon="${Y}◌${R}" ;;
            *approved*|*ready*)              icon="${C}●${R}" ;;
            *)                               icon="${D}?${R}" ;;
        esac
        printf "  %b  %-50s ${D}%s${R}\n" "$icon" "$fname" "$status"
    done
fi

echo ""
