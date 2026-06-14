# Aliases

# ── Shell ─────────────────────────────────────────────────────────────────────
alias rr = exec nu   # reload nushell (re-reads config.nu and env.nu)

# ── Files ────────────────────────────────────────────────────────────────────
alias ll = ls -l
alias la = ls -la

# ── Editor ───────────────────────────────────────────────────────────────────
alias ide = zed .
alias ocm = opencode -m ollama/gpt-mbx

# ── mise ─────────────────────────────────────────────────────────────────────
alias m   = mise
alias mr  = mise run
alias mi  = mise install
alias mt  = mise tasks ls

# ── Git (gitoxide) ───────────────────────────────────────────────────────────
# gix-supported: status, branch, log, fetch, clone, diff(objects), blame, worktree
# not yet in gix: add, commit, checkout/switch/restore, push, stash, rebase, merge
def --wrapped g    [...args] { gix ...$args }
def           gs   []        { gix status }
def --wrapped gb   [...args] { gix branch list ...$args }
def --wrapped ga   [...args] { git add ...$args }
def --wrapped gc   [...args] { git commit ...$args }
def --wrapped gco  [...args] { git checkout ...$args }
def --wrapped gd   [...args] { git diff ...$args }        # gix diff = object-level only
def           gl   []        { git pull --ff-only }
def --wrapped gp   [...args] { git push ...$args }
def --wrapped gpf  [...args] { git push --force-with-lease ...$args }
def gitgood [] { git stash; git pull --rebase; git stash pop; git push }

# ── GitHub CLI ───────────────────────────────────────────────────────────────
alias ghst   = gh auth status
alias ghrepo = gh repo view --web
alias ghpr   = gh pr create
alias ghprv  = gh pr view
alias ghprw  = gh pr view --web
alias ghiss  = gh issue list
alias ghrun  = gh run list

# ── BAML ─────────────────────────────────────────────────────────────────────
alias baml = uvx --from baml-py baml-cli

# ── Python / uv ──────────────────────────────────────────────────────────────
alias pip  = uv pip
alias pip3 = uv pip
alias py   = uv run python

# ── JS / Bun ─────────────────────────────────────────────────────────────────
alias npm  = bun
alias npx  = bunx
alias pnpm = bun
alias yarn = bun

# ── Zerobrew ─────────────────────────────────────────────────────────────────
alias zbi = zb install
alias zbl = zb list
alias zbu = zb update

# ── Dotfiles ─────────────────────────────────────────────────────────────────
alias dotfiles = cd ~/dotfiles
def --env dotgs   [] { cd ~/dotfiles; git status -sb }
def --env dotpull [] { cd ~/dotfiles; git pull --ff-only }
def --env dotpush [] { cd ~/dotfiles; git push }
def --env dotopen [] { cd ~/dotfiles; gh repo view --web }

# ── Docker / Colima ──────────────────────────────────────────────────────────
alias dps           = docker ps
alias dpsa          = docker ps -a
alias di            = docker images
alias dstop         = docker stop
alias drm           = docker rm
alias drmi          = docker rmi
alias drmif         = docker rmi -f
alias colima-start  = colima start --profile dev --cpu 4 --memory 6 --disk 60 --runtime docker
alias colima-stop   = colima stop --profile dev
alias colima-status = colima status --profile dev

# ── Kubernetes ───────────────────────────────────────────────────────────────
alias kctx   = kubectl config current-context
alias kpods  = kubectl get pods -A
alias kmpods = kubectl --context=gke_toptal-maestro_us-east1_main-0 -n team-maestro get pods
alias kmlogs = kubectl --context=gke_toptal-maestro_us-east1_main-0 -n team-maestro logs
alias kmexec = kubectl --context=gke_toptal-maestro_us-east1_main-0 -n team-maestro exec -it

# ── Maestro ──────────────────────────────────────────────────────────────────
alias ms     = maestro start
alias mst    = maestro stop
alias ml     = maestro list
alias mlogs  = maestro logs
alias mwork  = maestro work
alias mcfg   = maestro config show
alias mpurge = maestro purge
alias mauth  = maestro auth login

alias maestro-attach = docker exec -it -u vscode (docker ps --filter name=maestro-maestro-dev --format "{{.ID}}" | head -1) tmux -S /tmp/tmux-shared/maestro.sock -u attach-session

# ── Secrets / obfsck ─────────────────────────────────────────────────────────
alias obfs = pj secret redact
