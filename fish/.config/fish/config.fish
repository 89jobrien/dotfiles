if status is-interactive
    # Commands to run in interactive sessions can go here
    if test -d "$HOME/.zerobrew/bin"
        fish_add_path "$HOME/.zerobrew/bin"
    end
    if test -d "$HOME/.local/bin"
        fish_add_path "$HOME/.local/bin"
    end
    if test -d "$HOME/.local/share/mise/shims"
        fish_add_path --move --prepend "$HOME/.local/share/mise/shims"
    end
    if test -f "$HOME/.config/sops/age/keys.txt"
        set -gx MISE_SOPS_AGE_KEY_FILE "$HOME/.config/sops/age/keys.txt"
    end
    if command -q zb
        alias zbi "zb install"
        alias zbs "zb search"
        alias zbl "zb list"
        alias zbu "zb update"
    end
    if command -q uv
        alias pip "uv pip"
        alias pip3 "uv pip"
        alias py "uv run python"
    end
    if command -q bun
        alias npm "bun"
        alias npx "bunx"
        alias pnpm "bun"
        alias yarn "bun"
    end
    if command -q sccache
        set -gx RUSTC_WRAPPER sccache
    end

    # Core short aliases.
    alias m "mise"
    alias mr "mise run"
    alias mi "mise install"
    alias mt "mise tasks ls"

    alias g "git"
    alias gs "git status -sb"
    alias ga "git add"
    alias gc "git commit"
    alias gco "git checkout"
    alias gb "git branch"
    alias gl "git pull --ff-only"
    alias gp "git push"
    alias gd "git diff"

    # Dotfiles workflow helpers.
    alias dot "cd $HOME/dotfiles"
    alias dotgs "cd $HOME/dotfiles && git status -sb"
    alias dotpull "cd $HOME/dotfiles && git pull --ff-only"
    alias dotpush "cd $HOME/dotfiles && git push"

    function dfr --description "Run a mise task from ~/dotfiles"
        cd $HOME/dotfiles; and mise run $argv
    end

    function dfj --description "Run a just recipe from ~/dotfiles"
        cd $HOME/dotfiles; and just $argv
    end

    alias updev "dfr up"
    alias obs "dfr observe"
    alias obsk "dfr observe-k8s"
    alias obsl "dfr observe-logs"
    alias kctx "kubectl config current-context"
    alias kpods "kubectl get pods -A"

    function klogs --description "Tail logs across namespaces (stern)"
        set pattern "."
        if test (count $argv) -gt 0
            set pattern $argv[1]
        end
        stern $pattern -A
    end

    if command -q zoxide
        zoxide init fish | source
    end
end
