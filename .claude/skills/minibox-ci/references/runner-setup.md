# GHA Self-Hosted Runner Setup ($INFRA_VPS_HOST)

## Configuration

| Field | Value |
|---|---|
| Machine | $INFRA_VPS_HOST ($INFRA_VPS_IP) |
| User | `$INFRA_VPS_USER` |
| Runner dir | `~/actions-runner/` |
| Runner label | `minibox` |
| Workflow target | `runs-on: [self-hosted, minibox]` |
| Systemd scope | `--user` (runs as `dev`, no root) |

## Toolchain

- mise at `~/.local/bin/mise` — pins `rust = "1.88.0"` via repo `mise.toml`
- Runner service PATH does NOT include `~/.local/bin` — always use full path in CI steps
- `~/.cargo/bin` also not in service PATH — use `~/.local/bin/mise exec --` for all cargo calls

## CI Step Pattern

```yaml
- name: xtask unit tests
  run: ~/.local/bin/mise exec -- cargo xtask test-unit
```

## Runner Service Commands

SSH in first via `tools/ssh-jobrien.sh`, then:

```bash
# Status
systemctl --user status 'actions.runner.*'

# Restart
systemctl --user restart 'actions.runner.*'

# Logs
journalctl --user -u 'actions.runner.*' -n 100 --no-pager
```

## Re-registration (if runner goes offline)

```bash
cd ~/actions-runner
./svc.sh stop
./config.sh remove --token <TOKEN>   # get from repo Settings > Actions > Runners > New
./config.sh --url https://github.com/OWNER/REPO --token <TOKEN> --labels minibox --unattended
./svc.sh install
./svc.sh start
```

## What Runs in CI vs Locally

| Gate | Where | Command |
|---|---|---|
| fmt-check + clippy + build | Local pre-commit hook | `cargo xtask pre-commit` |
| nextest + coverage | Local pre-push hook | `cargo xtask prepush` |
| lib + handler + conformance tests | CI ($INFRA_VPS_HOST) | `cargo xtask test-unit` |
| e2e daemon+CLI tests | Manual (Linux+root) | `cargo xtask test-e2e-suite` |

**No compilation in GHA** — pre-commit/prepush handle it before push.
