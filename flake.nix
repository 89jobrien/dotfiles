{
  description = "Dotfiles — declarative CLI tools via Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems f;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          # ── Batch 1: CLI tools migrating from Homebrew ──────────────
          #
          # What stays in Brew (not listed here):
          #   Casks (raycast, zed, warp, github, codex, claude-code) — GUI apps
          #   colima, docker, docker-buildx, docker-compose — macOS container stack
          #   duti — macOS-only
          #   opencode, gemini-cli — not yet in nixpkgs
          #   zerobrew — proprietary
          #   git-flow-next — not in nixpkgs
          #   bacon, cargo-nextest, cargo-watch — Rust devtools via cargo/mise
          #   Language runtimes (node, bun, python, go, rust, uv) — managed by mise
          #   zsh-autosuggestions, zsh-autopair — Brew zsh plugins (path-dependent)
          #   mise — manages itself
          #   trunk, rust-analyzer, rust-script — Rust toolchain via mise/cargo
          #   cmake, pkgconf — build deps, keep in Brew for linker discoverability
          #   tilt — not reliably in nixpkgs
          #   btop — keep in Brew (ncurses linking quirks on macOS)

          cliPackages = with pkgs; [
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

            # Editor / shell
            tmux
            neovim
            stow

            # Git
            gh

            # Kubernetes
            kubectl
            kubectx
            kubernetes-helm
            k9s
            kind
            stern
          ];
        in
        {
          default = pkgs.buildEnv {
            name = "dotfiles-cli";
            paths = cliPackages;
            pathsToLink = [ "/bin" "/share/man" "/share/zsh" ];
          };

          # Alias for explicitness
          cli = self.packages.${system}.default;
        }
      );
    };
}
