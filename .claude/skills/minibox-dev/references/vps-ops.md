# VPS Operations (jobrien-vm)

## Connection

The VPS (`jobrien-vm`) is a Tailscale node at `100.105.75.7`. SSH password is stored in 1Password.

```bash
# Interactive SSH (preferred — uses Tailscale hostname alias)
mise run all:ssh-vps

# Via minibox-ci skill tools
~/.claude/skills/mbx/minibox-ci/tools/ssh-jobrien.sh "command"

# Direct (when tools unavailable)
sshpass -p "$(op item get jobrien-vm --account=my.1password.com --fields password --reveal)" \
  ssh -o IdentitiesOnly=yes -o IdentityAgent=none -o PreferredAuthentications=password \
  dev@100.105.75.7 "COMMAND"
```

## What Runs on VPS

| Service | Purpose |
|---|---|
| Gitea | Git hosting + CI runner (`cargo deny` + `cargo audit`) |
| GHA self-hosted runner | Future Linux CI for GitHub Actions |
| minibox-bench | Benchmark execution (consistent hardware) |
| Integration tests | Linux-only tests (cgroups, namespaces, e2e) |

## Benchmark Operations

```bash
# One-time setup (clone repo, build minibox-bench)
mise run all:bench:setup

# Run benchmarks on VPS, fetch results locally
cargo xtask bench-vps                    # run only
cargo xtask bench-vps --commit           # run + commit results
cargo xtask bench-vps --commit --push    # run + commit + push

# AI analysis of bench results
just bench-agent report                  # current results
just bench-agent compare SHA1 SHA2       # compare two runs
just bench-agent regress                 # detect regressions
```

Results pipeline:
- `bench/results/bench.jsonl` — append-only history
- `bench/results/latest.json` — canonical current snapshot

## Linux Testing on VPS

```bash
# SSH in, then run tests
mise run all:ssh-vps

# On VPS:
cd ~/minibox
cargo xtask test-unit                    # unit tests
sudo -E cargo test -p miniboxd --test cgroup_tests -- --test-threads=1 --nocapture
cargo xtask test-e2e-suite              # daemon+CLI e2e (requires root)
```

## Gitea CI

```bash
# Check CI status
mise run all:ci

# Set a secret
mise run all:ci:set-secret -- SECRET_NAME "value"
```

CI runs `cargo deny check` + `cargo audit` only — no compilation (VPS has 2 CPUs, no swap).
