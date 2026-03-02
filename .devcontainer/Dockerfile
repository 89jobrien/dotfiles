FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      git \
      stow \
      curl \
      jq \
      ripgrep \
      shellcheck \
    && rm -rf /var/lib/apt/lists/*
