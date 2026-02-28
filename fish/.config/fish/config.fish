if status is-interactive
    # History safety: commands containing likely secrets are not persisted.
    function fish_should_add_to_history --argument-names cmd
        set pattern '(OPENAI_API_KEY|ANTHROPIC_API_KEY|AWS_SECRET_ACCESS_KEY|GITHUB_TOKEN|GH_TOKEN|token=|api[_-]?key=|password=|passwd=|secret=|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]+)'
        if string match -r -i -- $pattern -- $cmd >/dev/null
            return 1
        end
        return 0
    end

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
    if command -q zed
        set -gx VISUAL "zed --wait"
        alias ide "zed ."
    else
        alias ide "nvim ."
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

    alias ghst "gh auth status"
    alias ghrepo "gh repo view --web"
    alias ghpr "gh pr create"
    alias ghprv "gh pr view"
    alias ghprw "gh pr view --web"
    alias ghiss "gh issue list"
    alias ghrun "gh run list"

    if command -q pj
        alias obfs "pj secret redact"
    end

    # Dotfiles workflow helpers.
    alias dot "cd $HOME/dotfiles"
    alias dotgs "cd $HOME/dotfiles && git status -sb"
    alias dotpull "cd $HOME/dotfiles && git pull --ff-only"
    alias dotpush "cd $HOME/dotfiles && git push"
    alias dotopen "cd $HOME/dotfiles && gh repo view --web"

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

    function obfsrun --description "Run command and redact output"
        if command -q pj
            eval $argv 2>&1 | pj secret redact
        else
            eval $argv
        end
    end

    if command -q zoxide
        zoxide init fish | source
    end
end
