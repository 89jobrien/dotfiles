---
name: env-debug
description: Use when op run fails with env conflicts, direnv isn't loading secrets, source_up chain is broken, Claude shell can't resolve op:// URIs, or secrets work in terminal but not in Claude context
---

# Env Debug

Systematic diagnosis of the secrets environment chain: direnv → source_up → 1Password → op run.

## The Chain

```
~/.envrc (or project .envrc)
  └── source_up
        └── ~/dev/.envrc
              └── op run --env-file ~/.secrets -- <cmd>
                    └── injects resolved op:// vars
```

**Claude's shell context cannot resolve `op://` URIs directly.** Always use `op read` or `op run` explicitly.

## Step 1: Check direnv

```bash
direnv status     # Allowed? Which .envrc loaded?
direnv allow      # Unblock current directory if needed
echo $DIRENV_DIR  # Should be set if active
```

## Step 2: Trace source_up chain

```bash
cat ~/.envrc
cat ~/dev/.envrc   # Walk up until you find the op run call
```

## Step 3: Diagnose op run conflicts

`op run` inherits the shell environment first. If a var is already set, it will **not** be overridden.

```bash
# See conflicting vars
env | grep -E "KEY|TOKEN|SECRET" | sort

# Clear specific conflicts before op run
env -u OPENAI_API_KEY -u ANTHROPIC_API_KEY op run --env-file ~/.secrets -- your-command

# Nuke all and re-inject
unset OPENAI_API_KEY ANTHROPIC_API_KEY
op run --account=my.1password.com --env-file ~/.secrets -- your-command
```

## Step 4: Verify op connectivity

```bash
op account list                        # Signed-in accounts
op signin --account my.1password.com   # Sign in if needed
op item list --account=my.1password.com --limit=3  # Test read access
```

## Step 5: Read a specific secret directly

```bash
op read "op://vault/item/field" --account=my.1password.com
# Example:
op read "op://Personal/OPENAI/credential" --account=my.1password.com
```

## Quick Diagnostic

```bash
echo "=== direnv ===" && direnv status
echo "=== op accounts ===" && op account list
echo "=== conflicting vars ===" && env | grep -E "KEY|TOKEN|SECRET" | sort
echo "=== op read test ===" && op item list --account=my.1password.com --limit=1
```

## Common Failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| `op://` not resolved in Claude | Shell can't use direnv | Use `op read` directly |
| `op run` ignores a secret | Var already in shell | `env -u VAR op run ...` |
| Secret works in terminal, not Claude | direnv not in Claude's shell | `op read` or `op run` explicitly |
| `op: not signed in` | Session expired | `op signin --account my.1password.com` |
| `direnv: .envrc not allowed` | direnv blocked | `direnv allow` |
| `source_up: no parent .envrc` | Chain broken | Check `~/dev/.envrc` exists |
| `grep ^KEY ~/.secrets` returns empty | Key name mismatch | `grep KEY ~/.secrets` to find exact name |
