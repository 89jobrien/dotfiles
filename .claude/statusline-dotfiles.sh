#!/usr/bin/env bash
# Claude Code status line for the dotfiles project.

input=$(cat)

CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; RESET='\033[0m'

# --- git ---
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
branch=$(git -C "$DOTFILES_DIR" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null \
         || git -C "$DOTFILES_DIR" --no-optional-locks rev-parse --short HEAD 2>/dev/null \
         || echo "?")
dirty=$(git -C "$DOTFILES_DIR" --no-optional-locks status --porcelain 2>/dev/null)
if [ -n "$dirty" ]; then
  git_part="${YELLOW}${branch}*${RESET}"
else
  git_part="${GREEN}${branch}${RESET}"
fi

# --- stow package count ---
pkg_file="$DOTFILES_DIR/config/stow-packages.txt"
local_pkg_file="$DOTFILES_DIR/config/stow-packages.local.txt"
pkg_count=0
if [ -f "$pkg_file" ]; then
  c=$(grep -c '^[^#[:space:]]' "$pkg_file" 2>/dev/null || true)
  pkg_count=${c:-0}
fi
if [ -f "$local_pkg_file" ]; then
  c=$(grep -c '^[^#[:space:]]' "$local_pkg_file" 2>/dev/null || true)
  pkg_count=$((pkg_count + ${c:-0}))
fi

# --- context + cost + model ---
used=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
used=${used%.*}; used=${used:-0}
cost=$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // 0' 2>/dev/null)
model=$(printf '%s' "$input" | jq -r '.model.display_name // "claude"' 2>/dev/null)

# context bar (10 chars)
filled=$((used * 10 / 100)); empty=$((10 - filled))
bar=$(printf "%${filled}s" | tr ' ' '▓')$(printf "%${empty}s" | tr ' ' '░')
if [ "$used" -ge 90 ]; then bar_color="$RED"
elif [ "$used" -ge 70 ]; then bar_color="$YELLOW"
else bar_color="$GREEN"; fi

cost_fmt=$(printf '$%.2f' "${cost:-0}" 2>/dev/null || echo '$0.00')

# line 1: project | git | stow
printf "${CYAN}dotfiles${RESET}  %b  stow:%d pkgs\n" "$git_part" "$pkg_count"
# line 2: context bar + cost + model
printf "${bar_color}%s${RESET} %d%%  %s  [%s]\n" "$bar" "$used" "$cost_fmt" "$model"
