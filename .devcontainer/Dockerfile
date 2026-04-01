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
RUN ARCH=$(dpkg --print-architecture) \
    && MISE_ARCH=$([ "$ARCH" = "arm64" ] && echo "arm64" || echo "x64") \
    && curl -fsSL "https://mise.jdx.dev/mise-latest-linux-${MISE_ARCH}" -o /usr/local/bin/mise \
    && chmod +x /usr/local/bin/mise

# shfmt — shell formatter (resolve latest version dynamically)
RUN ARCH=$(dpkg --print-architecture) \
    && SHFMT_VER=$(curl -sI https://github.com/mvdan/sh/releases/latest | grep -i ^location: | sed 's|.*/v||;s/\r//') \
    && curl -fsSL "https://github.com/mvdan/sh/releases/download/v${SHFMT_VER}/shfmt_v${SHFMT_VER}_linux_${ARCH}" \
       -o /usr/local/bin/shfmt \
    && chmod +x /usr/local/bin/shfmt

# just — task runner (mirrors Justfile interface)
RUN curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh \
    | bash -s -- --to /usr/local/bin

# gum — TUI elements used by scripts/lib/log.sh
RUN ARCH=$(dpkg --print-architecture) \
    && GUM_ARCH=$([ "$ARCH" = "arm64" ] && echo "arm64" || echo "x86_64") \
    && GUM_VER=$(curl -sI https://github.com/charmbracelet/gum/releases/latest | grep -i ^location: | sed 's|.*/v||;s/\r//') \
    && curl -fsSL "https://github.com/charmbracelet/gum/releases/download/v${GUM_VER}/gum_${GUM_VER}_Linux_${GUM_ARCH}.tar.gz" \
       | tar -xz -C /tmp \
    && mv /tmp/gum_${GUM_VER}_Linux_${GUM_ARCH}/gum /usr/local/bin/gum \
    && chmod +x /usr/local/bin/gum

ENV PATH="/usr/local/bin:$PATH"
