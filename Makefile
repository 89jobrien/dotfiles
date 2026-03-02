.PHONY: install doctor drift stow post nvim up container-start container-stop container-status compose-up compose-down compose-status compose-logs k3d-up k3d-down kind-up kind-down tilt-up observe observe-k8s observe-logs observe-docker observe-docker-events observe-docker-stats health health-live health-procs health-disk raycast-scripts personal-mcp ai-config maestro-setup maestro-where maestro-doctor maestro-up maestro-up-quick maestro-up-api maestro-handoff secrets-sops-json secrets-check

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

up: container-start k3d-up doctor

container-start:
	./scripts/container-dev.sh start

container-stop:
	./scripts/container-dev.sh stop

container-status:
	./scripts/container-dev.sh status

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

ai-config:
	./scripts/setup-ai-tools.sh

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

secrets-sops-json:
	./scripts/secrets/make-sops-env-json.sh

secrets-check:
	./scripts/secrets/check-no-plaintext.sh
