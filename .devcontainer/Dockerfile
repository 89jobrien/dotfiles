FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# System packages: core tools + script dependencies + test tooling
RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
      curl \
      wget \
      stow \
      jq \
      ripgrep \
      fd-find \
      fzf \
      shellcheck \
      bats \
      zsh \
      zsh-autosuggestions \
      tmux \
      unzip \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

# mise — runtime version manager (installs python, rust, go, node, bun, uv from .mise.toml)
RUN curl -fsSL https://mise.jdx.dev/mise-latest-linux-x64 -o /usr/local/bin/mise \
    && chmod +x /usr/local/bin/mise

# shfmt — shell formatter
RUN curl -fsSL "https://github.com/mvdan/sh/releases/latest/download/shfmt_v3_linux_amd64" \
      -o /usr/local/bin/shfmt \
    && chmod +x /usr/local/bin/shfmt

# just — task runner (mirrors Justfile interface)
RUN curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh \
    | bash -s -- --to /usr/local/bin

# gum — TUI elements used by scripts/lib/log.sh
RUN ARCH="x86_64" \
    && curl -fsSL "https://github.com/charmbracelet/gum/releases/latest/download/gum_Linux_${ARCH}.tar.gz" \
       | tar -xz -C /tmp \
    && mv /tmp/gum /usr/local/bin/gum \
    && chmod +x /usr/local/bin/gum

ENV PATH="/usr/local/bin:$PATH"
