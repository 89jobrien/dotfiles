#!/usr/bin/env fish
# mbx-context — quick context loader for minibox (fish)
# Usage: mbx-context [--brief | --full]

set REPO_ROOT (git rev-parse --show-toplevel 2>/dev/null; or echo $PWD)
cd $REPO_ROOT

function hdr; printf "\n\033[1m\033[36m  ── %s ──\033[0m\n\n" $argv; end

set MODE $argv[1]
test -z "$MODE"; and set MODE "--brief"

# ── Header ──
set VERSION (grep '^version' Cargo.toml | head -1 | sed 's/.*"\(.*\)"/\1/')
set RUST_VER (rustc --version 2>/dev/null | awk '{print $2}')
printf "\033[1m\033[36mminibox\033[0m v%s · %s · rust %s\n" $VERSION (uname -s) $RUST_VER

# ── Branch ──
hdr "branch"
set BRANCH (git branch --show-current 2>/dev/null; or echo "detached")
set COMMIT (git log -1 --format='%h %s (%cr)' 2>/dev/null)
printf "  \033[1m%s\033[0m · %s\n" $BRANCH $COMMIT

set DIRTY (git status --porcelain 2>/dev/null | wc -l | string trim)
if test $DIRTY -gt 0
    printf "  \033[33m%s dirty files\033[0m\n" $DIRTY
    git status --porcelain 2>/dev/null | head -10 | sed 's/^/    /'
    if test $DIRTY -gt 10
        printf "    \033[2m... and %d more\033[0m\n" (math $DIRTY - 10)
    end
end

# ── Crate Layout ──
hdr "crate layout"
printf "  \033[2mcrates/\033[0m\n"
for crate_dir in crates/*/
    set name (basename $crate_dir)
    if grep -q '^\[\[bin\]\]' $crate_dir/Cargo.toml 2>/dev/null
        set kind "bin"
    else
        set kind "lib"
    end
    set loc (find $crate_dir/src -name '*.rs' -exec cat '{}' + 2>/dev/null | wc -l | string trim)
    set deps (grep -cE '^\w.*=.*\{|^\w.*=.*"' $crate_dir/Cargo.toml 2>/dev/null; or echo 0)
    printf "    %-20s \033[2m%s · %5s lines · %2s deps\033[0m\n" $name $kind $loc $deps
end
printf "  \033[2mxtask/\033[0m\n"
printf "    %-20s \033[2mbin · dev tool\033[0m\n" "xtask"

# ── Recent Commits ──
hdr "recent commits (7d)"
git log --oneline --since="7 days ago" --no-merges --format="  %C(auto)%h%C(reset) %s %C(dim)(%cr)%C(reset)" 2>/dev/null | head -15

set TOTAL_7D (git log --oneline --since="7 days ago" --no-merges 2>/dev/null | wc -l | string trim)
if test $TOTAL_7D -gt 15
    printf "  \033[2m... and %d more\033[0m\n" (math $TOTAL_7D - 15)
end

# ── Full mode ──
if test "$MODE" = "--full"
    hdr "adapter suites"
    printf "  \033[32m●\033[0m  native    \033[2mLinux namespaces, overlay, cgroups v2\033[0m\n"
    printf "  \033[32m●\033[0m  gke       \033[2mproot, copy FS, no-op limiter\033[0m\n"
    printf "  \033[32m●\033[0m  colima    \033[2mmacOS via limactl/nerdctl\033[0m\n"
    printf "  \033[2m○\033[0m  vf        \033[2mVirtualization.framework (not wired)\033[0m\n"
    printf "  \033[2m○\033[0m  wsl2      \033[2mWSL2 (not wired)\033[0m\n"
    printf "  \033[2m○\033[0m  hcs       \033[2mWindows HCS (not wired)\033[0m\n"

    hdr "domain traits"
    grep -n 'pub trait' crates/minibox-lib/src/domain.rs 2>/dev/null | while read -l line
        set trait_name (echo $line | sed 's/.*pub trait \([A-Za-z]*\).*/\1/')
        set line_no (echo $line | cut -d: -f1)
        set impls (grep -rl "impl.*$trait_name" crates/ 2>/dev/null | wc -l | string trim)
        printf "  %-24s \033[2mL%s · %s impl(s)\033[0m\n" $trait_name $line_no $impls
    end

    hdr "plans + specs"
    for f in docs/plans/*.md docs/superpowers/specs/*.md docs/superpowers/plans/*.md
        test -f $f; or continue
        set status (head -5 $f | grep -i 'status:' | sed 's/.*status: *//' | string trim)
        set fname (basename $f)
        switch $status
            case '*implemented*' '*complete*' '*done*'
                set icon "\033[32m✓\033[0m"
            case '*draft*' '*proposed*'
                set icon "\033[33m◌\033[0m"
            case '*approved*' '*ready*'
                set icon "\033[36m●\033[0m"
            case '*'
                set icon "\033[2m?\033[0m"
        end
        printf "  %b  %-50s \033[2m%s\033[0m\n" $icon $fname $status
    end
end

echo ""
