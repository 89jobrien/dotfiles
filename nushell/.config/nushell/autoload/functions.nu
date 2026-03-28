# Custom functions

# ── Files ────────────────────────────────────────────────────────────────────

# Quick directory listing sorted by size
def dirsize [] {
    ls | select name size type | sort-by size -r
}

# Make a directory and cd into it
def --env mkcd [dir: string] {
    mkdir $dir
    cd $dir
}

# ── Dotfiles ─────────────────────────────────────────────────────────────────

# Run a mise task from the dotfiles repo
def dfr [...args: string] {
    let root = ($env.HOME | path join "dotfiles")
    ^mise --cd $root run ...$args
}

# Run a just recipe from the dotfiles repo
def dfj [...args: string] {
    let root = ($env.HOME | path join "dotfiles")
    ^just --justfile $"($root)/Justfile" ...$args
}

# ── Kubernetes ───────────────────────────────────────────────────────────────

# Tail logs across all namespaces (uses stern)
def klogs [pattern: string = "."] {
    ^stern $pattern -A
}

# ── Secrets / redaction ──────────────────────────────────────────────────────

# Run a command and pipe output through pj secret redact
def obfsrun [...args: string] {
    if (which pj | is-not-empty) {
        ^$args.0 ...$args | skip 1 | ^pj secret redact
    } else {
        ^$args.0 ...$args | skip 1
    }
}

# ── Docker / Colima ──────────────────────────────────────────────────────────

def _colima_ensure_running [] {
    if (which colima | is-empty) { return }
    let profile = if ("COLIMA_PROFILE" in $env) { $env.COLIMA_PROFILE } else { "dev" }
    let running = (^colima status --profile $profile | complete | get exit_code) == 0
    if not $running {
        print $"[colima] Starting profile '($profile)' \(4 CPU, 6GB RAM, 60GB disk\)..."
        ^colima start --profile $profile --cpu 4 --memory 6 --disk 60 --runtime docker
    }
}

def _colima_set_socket [] {
    let dev_sock = ($env.HOME | path join ".colima/dev/docker.sock")
    let default_sock = ($env.HOME | path join ".config/colima/default/docker.sock")
    if ($dev_sock | path exists) {
        $env.DOCKER_HOST = $"unix://($dev_sock)"
    } else if ($default_sock | path exists) {
        $env.DOCKER_HOST = $"unix://($default_sock)"
    }
}

def --wrapped docker [...args: string] {
    _colima_ensure_running
    _colima_set_socket
    ^docker ...$args
}

def --wrapped docker-compose [...args: string] {
    _colima_ensure_running
    _colima_set_socket
    ^docker-compose ...$args
}

alias colima-restart = (colima-stop; colima-start)

# ── JS ───────────────────────────────────────────────────────────────────────

# Real npm bypass (bun alias doesn't cover maestro-ui which needs real npm)
def mnpm [...args: string] {
    ^npm ...$args
}

# ── Git helpers ──────────────────────────────────────────────────────────────

# Push via gh credential helper
def _git_gh [...args: string] {
    ^git -c credential.helper= -c "credential.helper=!/opt/homebrew/bin/gh auth git-credential" ...$args
}
