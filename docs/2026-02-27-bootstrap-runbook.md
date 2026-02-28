# 2026-02-27 Bootstrap Runbook

This records the exact sequence that worked well on the Mac mini.

## What We Changed

1. Switched to a `mise`-first workflow for daily dev tasks.
2. Added `Justfile` parity for AI/automation recipes.
3. Installed Alacritty from source (cargo), not Homebrew cask.
4. Set up Colima + k3d local Kubernetes workflow.
5. Added observability commands (`observe*`) for runtime, cluster, logs, and docker streams.
6. Hardened `.gitignore` for machine-local state and removed noisy tracked files.

## Key Commands Used

```bash
# One-command bring-up
mise run up

# Visualize runtime and cluster
mise run observe
mise run observe-k8s
mise run observe-logs

# If Colima profile was previously containerd-based:
colima delete --profile dev --data -f
mise run container-start
mise run k3d-up
```

## Colima Runtime Migration Note

If you ever see:

`runtime disk provisioned for containerd runtime`

you must reset the Colima profile data once:

```bash
colima delete --profile dev --data -f
```

Then rerun start and cluster creation.

## Git Hygiene Result

Before cleanup, the repo head tracked mostly local app-state files (`raycast`, `mcpm`, `vector`).

After cleanup and commit:

```bash
git ls-tree -r --name-only HEAD | wc -l
# -> 7
```

This means only intentional baseline files remained in `HEAD` before scaffold commit, and local machine state is now excluded by `.gitignore`.

## Commits from This Session

- `cb1c78e` `chore(git): ignore and de-index local app state`
- `a247c92` `feat(bootstrap): add mise-first dev env automation and observability`
