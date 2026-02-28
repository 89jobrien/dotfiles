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
end
