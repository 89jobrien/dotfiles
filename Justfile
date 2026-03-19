set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

install:
    ./install.sh

doctor:
    ./scripts/doctor.sh

drift:
    ./scripts/drift-check.sh

stow:
    ./install.sh --no-packages --no-post

post:
    ./install.sh --no-packages --no-stow

dot:
    ./install.sh --dot-only

nvim:
    ./scripts/setup-nvchad-avante.sh

up:
    just container-start
    just k3d-up
    just doctor

container-start:
    ./scripts/container-dev.sh start

container-stop:
    ./scripts/container-dev.sh stop

container-status:
    ./scripts/container-dev.sh status

colima-autostart-enable:
    ./colima/scripts/enable-autostart.sh

colima-autostart-disable:
    ./colima/scripts/disable-autostart.sh

compose-up:
    ./scripts/compose-dev.sh up

compose-down:
    ./scripts/compose-dev.sh down

compose-status:
    ./scripts/compose-dev.sh status

compose-logs:
    ./scripts/compose-dev.sh logs

k3d-up:
    ./scripts/container-dev.sh k3d-up

k3d-down:
    ./scripts/container-dev.sh k3d-down

kind-up:
    ./scripts/container-dev.sh kind-up

kind-down:
    ./scripts/container-dev.sh kind-down

tilt-up:
    ./scripts/container-dev.sh tilt-up

observe:
    ./scripts/observe-dev.sh summary

observe-k8s:
    ./scripts/observe-dev.sh k8s

observe-logs:
    ./scripts/observe-dev.sh logs

observe-docker:
    ./scripts/observe-dev.sh docker

observe-docker-events:
    ./scripts/observe-dev.sh docker-events

observe-docker-stats:
    ./scripts/observe-dev.sh docker-stats

health:
    ./scripts/system-health.sh summary

health-live:
    ./scripts/system-health.sh live

health-procs:
    ./scripts/system-health.sh procs

health-disk:
    ./scripts/system-health.sh disk

raycast-scripts:
    ./scripts/setup-macos.sh

personal-mcp:
    ./scripts/setup-ai-tools.sh

mcp-build:
    KEEP_BUILD_ARTIFACTS=1 ./scripts/setup-ai-tools.sh

ai-config:
    ./scripts/setup-ai-tools.sh

hooks-install:
    ./scripts/setup-hooks.sh

maestro-setup:
    ./scripts/setup-maestro.sh

maestro-where:
    ./scripts/maestro-dev.sh where

maestro-doctor:
    ./scripts/maestro-dev.sh doctor

maestro-up:
    ./scripts/maestro-dev.sh up

maestro-up-quick:
    ./scripts/maestro-dev.sh up --quick

maestro-up-api:
    ./scripts/maestro-dev.sh up --api-run

maestro-handoff:
    ./scripts/maestro-dev.sh handoff

companion-repos:
    ./scripts/setup-companion-repos.sh

ts-devices:
    ./tailscale/scripts/parse-devices.sh list

ts-ssh:
    ./tailscale/scripts/generate-ssh-config.sh

ts-expiry:
    ./tailscale/scripts/check-expiry.sh

ts-refresh CSV:
    ./tailscale/scripts/refresh-devices.sh {{CSV}}

ssh-sync:
    ./ssh-tools/scripts/sync-keys.sh

ssh-sync-dry-run:
    DRY_RUN=1 ./ssh-tools/scripts/sync-keys.sh

tasks:
    ./scripts/tasks-interactive.sh

update-check:
    ./scripts/check-updates.sh

update:
    ./scripts/update-dotfiles.sh

nix-install:
    ./scripts/setup-nix.sh

nix-update:
    nix flake update && ./scripts/setup-nix.sh

nix-check:
    nix profile list && nix flake check

rust-clean:
    ./scripts/rust-clean.sh

rust-clean-dry:
    ./scripts/rust-clean.sh --dry-run

rust-clean-service-install:
    ./scripts/rust-clean-service.sh install

rust-clean-service-uninstall:
    ./scripts/rust-clean-service.sh uninstall

rust-clean-service-status:
    ./scripts/rust-clean-service.sh status

rust-clean-service-run-now:
    ./scripts/rust-clean-service.sh run-now

rust-clean-service-logs:
    ./scripts/rust-clean-service.sh logs

secrets-sops-json:
    ./scripts/secrets/make-sops-env-json.sh

secrets-check:
    ./scripts/secrets/check-no-plaintext.sh

secrets-setup:
    ./scripts/setup-secrets-interactive.sh

toolz-install:
    cargo install --path ~/dev/tools --root "${HOME}/.local" --force

toolz-dev:
    cd ~/dev/tools && cargo build

rust-tools:
    ./scripts/setup-rust-tools.sh

menu:
    ./scripts/menu
