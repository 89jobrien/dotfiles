#!/usr/bin/env bash
# Claude Code status line — mirrors Oh My Zsh robbyrussell theme
# Receives JSON on stdin from Claude Code

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# Basename of cwd (robbyrussell shows only the last path component)
dir=$(basename "${cwd:-$(pwd)}")

# Git branch (skip optional locks for safety in read-only contexts)
branch=""
if git_branch=$(GIT_OPTIONAL_LOCKS=0 git -C "${cwd:-.}" symbolic-ref --short HEAD 2>/dev/null); then
  branch="$git_branch"
elif git_branch=$(GIT_OPTIONAL_LOCKS=0 git -C "${cwd:-.}" rev-parse --short HEAD 2>/dev/null); then
  branch="$git_branch"
fi

# ANSI colours (will be dimmed by the terminal as Claude Code applies its own styling)
RESET='\033[0m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
MAGENTA='\033[0;35m'

# Build the prompt segments
prompt=""

# Directory
prompt+="$(printf "${CYAN}%s${RESET}" "${dir}")"

# Git branch
if [ -n "$branch" ]; then
  prompt+=" $(printf "${GREEN}git:(${MAGENTA}%s${GREEN})${RESET}" "${branch}")"
fi

# Model
if [ -n "$model" ]; then
  prompt+=" $(printf "${YELLOW}[%s]${RESET}" "${model}")"
fi

# Context window remaining
if [ -n "$remaining" ]; then
  remaining_int=${remaining%.*}
  if [ "${remaining_int:-100}" -le 20 ]; then
    CTX_COLOR='\033[0;31m'   # red when low
  else
    CTX_COLOR='\033[0;32m'   # green otherwise
  fi
  prompt+=" $(printf "${CTX_COLOR}ctx:%s%%%s" "${remaining_int}" "${RESET}")"
fi

printf "%b\n" "$prompt"
