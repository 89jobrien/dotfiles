# Custom functions

# ── nu_libs ──────────────────────────────────────────────────────────────────

# Show all commands loaded from nu_libs, grouped by domain
def libs [
    --filter(-f): string = ""  # filter by name substring
] {
    let nu_libs_dir = "/Users/joe/dev/nu_libs/lib"

    # Build name→domain map by scanning export defs in each domain's files
    let domain_map = (
        ls $nu_libs_dir
        | where type == "dir"
        | get name
        | each {|dir|
            let domain = $dir | path basename
            let names = (
                glob $"($dir)/**/*.nu"
                | each {|f|
                    open $f | lines
                    | where {|l| ($l | str starts-with "export def") or ($l | str starts-with "export alias")}
                    | each {|l|
                        # extract the command name: third or fourth word depending on flags
                        let parts = $l | split row " " | where {|p| ($p | str length) > 0}
                        # skip "export", "def"/"alias", and any --flags
                        $parts | skip 2 | where {|p| not ($p | str starts-with "-")} | first
                    }
                    | compact
                }
                | flatten
                | compact
                | each {|n| $n | str replace --all '"' "" | str replace --all "`" "" | str trim}
            )
            $names | each {|n| {name: $n, domain: $domain}}
        }
        | flatten
        | uniq-by name
        | reduce -f {} {|x, acc| $acc | upsert $x.name $x.domain}
    )

    let nu_libs_names = $domain_map | columns

    help commands
    | where command_type == "custom"
    | where {|cmd| $cmd.name in $nu_libs_names}
    | if ($filter | is-not-empty) { where name =~ $filter } else { $in }
    | select name description
    | each {|cmd|
        $cmd | insert domain ($domain_map | get $cmd.name)
    }
    | sort-by domain name
    | group-by domain
    | transpose domain cmds
    | each {|g|
        print $"(ansi cyan_bold)── ($g.domain) ──(ansi reset)"
        $g.cmds | select name description | print
    }
    null
}

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

# Run a command and pipe its output through obfsck redact
def obfsrun [...args: string] {
    let config = ($nu.home-path | path join "dotfiles/config/obfsck-secrets.yaml")
    if (which obfsck | is-not-empty) {
        ^$args.0 ...($args | skip 1) | ^obfsck --config $config
    } else {
        ^$args.0 ...($args | skip 1)
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

def colima-restart [] {
    colima-stop
    colima-start
}

# ── JS ───────────────────────────────────────────────────────────────────────

# Real npm bypass (bun alias doesn't cover maestro-ui which needs real npm)
def mnpm [...args: string] {
    ^npm ...$args
}

# ── Secrets helpers ──────────────────────────────────────────────────────────

# Run a command with secrets injected from ~/.secrets via op run.
# Works around $HOME not being expanded by op CLI.
def oprun [...args: string] {
    let secrets = ($env.HOME | path join ".secrets")
    ^op run --account=my.1password.com $"--env-file=($secrets)" -- ...$args
}

# ── Git helpers ──────────────────────────────────────────────────────────────

# Push via gh credential helper
def _git_gh [...args: string] {
    ^git -c credential.helper= -c "credential.helper=!/opt/homebrew/bin/gh auth git-credential" ...$args
}
