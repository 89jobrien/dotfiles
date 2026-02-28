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

secrets-sops-json:
    ./scripts/secrets/make-sops-env-json.sh
