# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git)

if [ -f "$ZSH/oh-my-zsh.sh" ]; then
  source "$ZSH/oh-my-zsh.sh"
fi

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
[ -d "$HOME/.zerobrew/bin" ] && export PATH="$HOME/.zerobrew/bin:$PATH"
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"

if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi

# Prefer mise shims first for reproducible tool resolution.
export PATH="$HOME/.local/share/mise/shims:$PATH"

if [ -f "$HOME/.config/sops/age/keys.txt" ]; then
  export MISE_SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
fi

if command -v zb >/dev/null 2>&1; then
  alias zbi='zb install'
  alias zbs='zb search'
  alias zbl='zb list'
  alias zbu='zb update'
fi

# Default IDE preference: Zed when available.
if command -v zed >/dev/null 2>&1; then
  export VISUAL='zed --wait'
  alias ide='zed .'
else
  alias ide='nvim .'
fi

# History safety: commands containing likely secrets are not persisted.
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
zshaddhistory() {
  emulate -L zsh
  local line="${1%%$'\n'}"
  local pat='(OPENAI_API_KEY|ANTHROPIC_API_KEY|AWS_SECRET_ACCESS_KEY|GITHUB_TOKEN|GH_TOKEN|token=|api[_-]?key=|password=|passwd=|secret=|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]+)'
  [[ "$line" =~ ${~pat} ]] && return 1
  return 0
}

# Prefer uv for Python workflows.
if command -v uv >/dev/null 2>&1; then
  alias pip='uv pip'
  alias pip3='uv pip'
  alias py='uv run python'
fi

# Prefer Bun for JS package management where compatible.
if command -v bun >/dev/null 2>&1; then
  alias npm='bun'
  alias npx='bunx'
  alias pnpm='bun'
  alias yarn='bun'
fi

if command -v sccache >/dev/null 2>&1; then
  export RUSTC_WRAPPER='sccache'
fi

# Core short aliases.
alias m='mise'
alias mr='mise run'
alias mi='mise install'
alias mt='mise tasks ls'

alias g='git'
alias gs='git status -sb'
alias ga='git add'
alias gc='git commit'
alias gco='git checkout'
alias gb='git branch'
alias gd='git diff'
_git_gh() {
  git -c credential.helper= -c credential.helper='!/opt/homebrew/bin/gh auth git-credential' "$@"
}
gp() { _git_gh push "$@"; }
gl() { _git_gh pull --ff-only "$@"; }
gpf() { _git_gh push --force-with-lease "$@"; }
if git flow version >/dev/null 2>&1; then
  alias gfi='git flow init -fd'
  alias gffs='git flow feature start'
  alias gfff='git flow feature finish'
  alias gfrs='git flow release start'
  alias gfrf='git flow release finish'
  alias gfhs='git flow hotfix start'
  alias gfhf='git flow hotfix finish'
fi

alias ghst='gh auth status'
alias ghrepo='gh repo view --web'
alias ghpr='gh pr create'
alias ghprv='gh pr view'
alias ghprw='gh pr view --web'
alias ghiss='gh issue list'
alias ghrun='gh run list'

if command -v pj >/dev/null 2>&1; then
  alias obfs='pj secret redact'
fi

# Redact command output with obfsck-style tokens.
obfsrun() {
  if command -v pj >/dev/null 2>&1; then
    "$@" 2>&1 | pj secret redact
  else
    "$@"
  fi
}

# Dotfiles workflow helpers.
alias dot='cd "$HOME/dotfiles"'
alias dotgs='cd "$HOME/dotfiles" && git status -sb'
alias dotpull='cd "$HOME/dotfiles" && git pull --ff-only'
alias dotpush='cd "$HOME/dotfiles" && git push'
alias dotopen='cd "$HOME/dotfiles" && gh repo view --web'

dfr() {
  (cd "$HOME/dotfiles" && mise run "$@")
}

dfj() {
  (cd "$HOME/dotfiles" && just "$@")
}

alias updev='dfr up'
alias obs='dfr observe'
alias obsk='dfr observe-k8s'
alias obsl='dfr observe-logs'
alias kctx='kubectl config current-context'
alias kpods='kubectl get pods -A'

# Tail logs across all namespaces with optional stern pattern.
klogs() {
  local pattern="${1:-.}"
  stern "${pattern}" -A
}

# Auto-load decrypted bootstrap secrets (dotenv format).
if [ -f "$HOME/.config/dev-bootstrap/secrets.env" ]; then
  set -a
  . "$HOME/.config/dev-bootstrap/secrets.env"
  set +a
fi

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi
if [ -f /opt/homebrew/share/zsh-autopair/autopair.zsh ]; then
  source /opt/homebrew/share/zsh-autopair/autopair.zsh
fi
if [ -f /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]; then
  source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

# Mutable local overrides (not managed by stow repo)
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
