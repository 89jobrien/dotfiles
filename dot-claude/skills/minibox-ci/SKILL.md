---
name: minibox-ci
description: Use when working on minibox CI, managing the self-hosted GHA runner on $INFRA_VPS_HOST, running xtask gates, or diagnosing CI failures. Symptoms - CI failing, runner offline, mise not found, xtask error, need to SSH into $INFRA_VPS_HOST.
---

# Minibox CI & Runner Ops

## References

- [references/runner-setup.md](references/runner-setup.md) — Runner config, toolchain PATH quirks, re-registration steps, CI vs local gate breakdown
- [references/xtask-reference.md](references/xtask-reference.md) — Every xtask command, which crates it covers, when to use each

## Tools

- [tools/ssh-jobrien.sh](tools/ssh-jobrien.sh) — SSH to $INFRA_VPS_HOST via 1Password. `./ssh-jobrien.sh "command"` or interactive.
- [tools/runner-status.sh](tools/runner-status.sh) — Check GHA runner units/status. `./runner-status.sh [logs]`
- [tools/ci-status.sh](tools/ci-status.sh) — Latest CI run status. `./ci-status.sh [watch|logs [ID]]`

## Quick Reference

### SSH to $INFRA_VPS_HOST

```bash
# Via tool (preferred)
~/.claude/skills/mbx/minibox-ci/tools/ssh-jobrien.sh "COMMAND"

# Inline (when tool not convenient)
sshpass -p "$(op item get $INFRA_VPS_HOST --account=my.1password.com --fields password --reveal)" \
  ssh -o IdentitiesOnly=yes -o IdentityAgent=none -o PreferredAuthentications=password \
  dev@100.105.75.7 "COMMAND"
```

### xtask Gates

```bash
cargo xtask pre-commit      # fmt-check + clippy + build (macOS-safe, pre-commit hook)
cargo xtask prepush         # nextest + coverage (pre-push hook)
cargo xtask test-unit       # lib + handler + conformance tests (CI step)
cargo xtask test-e2e-suite  # daemon+CLI e2e (Linux + root)
```

### CI Diagnostics

```bash
gh run list --workflow=ci.yml --limit 5
gh run watch $(gh run list --workflow=ci.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run view <ID> --log-failed
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| `mise` not found in CI | Use `~/.local/bin/mise exec --` prefix |
| Compilation in GHA | Don't — pre-commit/prepush handle it locally |
| `cargo test -p miniboxd --lib` | No lib tests exist — skip it (exit code 4) |
| `--workspace` on macOS | Fails on miniboxd — use explicit `-p` flags |
