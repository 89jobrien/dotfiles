---
name: using-maestro
description: Use when working on the Maestro project — K8s pod management, Tilt local dev, GKE deployments, Go+Rust codegen, n8n workflows, or Maestro CLI development
---

# Using Maestro

## Overview

Maestro orchestrates developer environments on K8s. Go API + Rust CLI. Runs on GKE (prod/staging) and k3d (local via Tilt).

## Project Layout

```
/Users/joe/dev/maestro/
├── api/          # Go API server (K8s pod lifecycle, n8n, E2E runner)
├── cli/          # Rust CLI (maestro binary, auth, pod commands)
├── infra/        # Terraform + Helm charts
├── tilt/         # Tiltfiles and local dev config
└── Makefile      # build, test, lint, dev-setup, install-hooks
```

## Local Dev (Tilt)

```bash
tilt up                    # Start k3d cluster + all services
tilt logs -f <resource>    # Stream logs
tilt trigger <resource>    # Force rebuild one resource
tilt down                  # Tear down (safe — only local)
```

Tilt watches source files and rebuilds containers on change. Let it manage rebuilds — don't restart services manually.

## GKE Context

```bash
# Authenticate (once per session or when token expires)
gcloud auth login
gcloud container clusters get-credentials main-0 --region us-east1 --project toptal-maestro

# Verify
kubectl config current-context
# → gke_toptal-maestro_us-east1_main-0

# Switch back to local k3d
kubectl config use-context k3d-maestro
```

## Common kubectl Operations

```bash
kubectl get pods -n sessions                            # List active session pods
kubectl logs -n sessions <pod> --tail=100               # Pod logs
kubectl describe pod -n sessions <pod>                  # Events, resource limits, status
kubectl port-forward svc/maestro-api 8080:8080 -n maestro  # Local API access
kubectl get events -n sessions --sort-by=.lastTimestamp # Recent events
```

## Safety Rules

| Rule | Reason |
|------|--------|
| Never delete pods without `--selector` or explicit pod name | Risk of terminating active dev sessions |
| Never run `kubectl delete all` in `sessions` namespace | Destroys all active environments |
| Check `$MAESTRO_CONTAINER_ID` before any `docker rm`/`stop` | May terminate own container |
| Infrastructure changes (Terraform/Helm): propose plan, get approval | See `infrastructure-plan-first` skill |
| Never reset shared service credentials | Affects all developers |

## Go Conventions

- Interfaces at consumption site (not in implementation package)
- Errors wrapped with `%w` for chain inspection
- Context as first argument on all service/handler methods
- `go test ./... -race` before commits
- Coverage ≥80% on `api/` packages

## Rust CLI Conventions

- Edition 2024, hexagonal arch (`cli/domain/`, `cli/adapters/`)
- `cargo clippy -- -D warnings` and `cargo fmt` must pass
- Auth tokens via `keyring` crate (OS keychain), never plaintext

## Build & Test

```bash
make build          # Build API + CLI
make test           # All tests
make lint           # go vet + cargo clippy
make install-hooks  # pre-commit, pre-push
```

## Common Issues

| Issue | Fix |
|-------|-----|
| Colima not running | `colima start` |
| gcloud auth expired | `gcloud auth login` |
| kubectl context wrong | `gcloud container clusters get-credentials main-0 --region us-east1 --project toptal-maestro` |
| Tilt file watch limit | `ulimit -n 10000` |
| `maestro auth` expired | `MAESTRO_API_URL=https://api.maestro-staging.toptal.net maestro auth login` |
