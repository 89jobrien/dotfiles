{ config, pkgs, lib, ... }:

{
  home.username = "nixos";
  home.homeDirectory = "/home/nixos";
  home.stateVersion = "24.05";

  programs.home-manager.enable = true;

  # ── Packages ──────────────────────────────────────────────────────────────
  # Mirrors cliPackages in flake.nix (Nix profile for macOS/Linux).
  # Runtimes (go, node, python, rust, bun) are managed by mise, not nix.
  home.packages = with pkgs; [
    # Rust CLI replacements
    ripgrep
    fd
    bat
    eza
    zoxide
    tokei
    dust
    duf
    procs
    bottom
    btop

    # Utilities
    jq
    yq-go
    fzf
    gum
    age
    sops
    shellcheck
    direnv
    just
    mise        # runtime version manager (node, python, go, rust, bun)

    # Editor / shell / multiplexer
    neovim
    tmux

    # Git
    gh
    git-delta

    # Kubernetes
    kubectl
    kubectx
    kubernetes-helm
    k9s
    kind
    stern

    # Build tools
    gnumake
    cmake
    pkg-config
  ];

  # ── Git ───────────────────────────────────────────────────────────────────
  programs.git = {
    enable = true;
    delta.enable = true;
    extraConfig = {
      core.autocrlf = "input";
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  # ── Zsh ───────────────────────────────────────────────────────────────────
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    historySubstringSearch.enable = true;

    history = {
      size = 50000;
      save = 50000;
      share = true;
      ignoreDups = true;
      ignoreSpace = true;
    };

    initExtra = ''
      # mise — activate runtime version manager
      if command -v mise &>/dev/null; then
        eval "$(mise activate zsh)"
      fi

      # direnv
      if command -v direnv &>/dev/null; then
        eval "$(direnv hook zsh)"
      fi

      # Source dotfiles .zshrc extras if present (stowed from repo)
      [[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
    '';

    shellAliases = {
      l   = "eza --icons";
      ll  = "eza -l --icons --git";
      la  = "eza -la --icons --git";
      lt  = "eza --tree --icons";
      cat = "bat";
      grep = "rg";
      vim = "nvim";
      vi  = "nvim";
    };
  };

  # ── Starship prompt ───────────────────────────────────────────────────────
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      add_newline = false;
      character = {
        success_symbol = "[>](bold green)";
        error_symbol   = "[>](bold red)";
      };
    };
  };

  # ── Zoxide (smart cd) ─────────────────────────────────────────────────────
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  # ── Direnv ────────────────────────────────────────────────────────────────
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # ── Neovim ────────────────────────────────────────────────────────────────
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    vimAlias = true;
  };

  # ── FZF ───────────────────────────────────────────────────────────────────
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  # ── Tmux ──────────────────────────────────────────────────────────────────
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    historyLimit = 10000;
    keyMode = "vi";
    extraConfig = ''
      set -g mouse on
      set -g renumber-windows on
    '';
  };
}
