---
name: env-chain-tracer
description: Use when env vars are missing, wrong, or when debugging why `op run` or `direnv` isn't loading the right secrets. Traces the full source_up chain from project to root, showing which .envrc files are loaded and what each one injects.
---

# env-chain-tracer

Trace the full direnv `source_up` chain for any project directory. Maps which `.envrc` files are loaded, which `op://` references each one injects, and which environment variables end up in scope.

## Quick Trace

Walk up from `$PWD` to `$HOME` and print every `.envrc` found:

```bash
dir="$PWD"; while [[ "$dir" != "/" && "$dir" != "$HOME/.." ]]; do [[ -f "$dir/.envrc" ]] && echo "=== $dir/.envrc ===" && cat "$dir/.envrc"; dir="$(dirname "$dir")"; done
```

## Step-by-Step Chain Analysis

### 1. Find All .envrc Files in Chain

Walk from the project directory up to `$HOME`, listing each `.envrc` found:

```bash
dir="$PWD"
while [[ "$dir" != "/" && "$dir" != "$HOME/.." ]]; do
  [[ -f "$dir/.envrc" ]] && echo "$dir/.envrc"
  dir="$(dirname "$dir")"
done
```

Read each file discovered using the Read tool (not `cat`).

### 2. Read Each .envrc

For each file found, look for:

- `source_up` calls — chain continues upward; the parent directory's `.envrc` will also be loaded
- `export VAR=value` — direct variable exports; note order relative to `source_up`
- `op run --env-file FILE` — 1Password injection; note the `--env-file` path
- `dotenv FILE` — loads a `.env` file into the environment
- `use mise` / `use node` / `layout python` — runtime version pins (not secrets, but affect PATH)

Order matters: variables exported before `source_up` can be overridden by the parent; variables exported after `source_up` take precedence over the parent.

### 3. Parse op:// References

If an `--env-file` is referenced in the chain, read that file and show all `op://` references — var names only, never values:

```bash
cat ~/.secrets | grep "op://" | sed 's/=.*//'  # show var names only (never values)
```

Use the Read tool on the env-file path to inspect it safely. Mask any line that contains an actual resolved value.

### 4. Check What's Actually Loaded

```bash
direnv status        # Is direnv active? Which .envrc is loaded?
direnv export bash   # What vars would be exported (dry run, safe to run)
```

`direnv export bash` does not modify the environment — it only prints what would be set. Use it freely for diagnosis.

### 5. Common source_up Failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| `source_up: no parent .envrc found` | Chain broken above project dir | Create `~/dev/.envrc` if missing |
| Var set in parent `.envrc` but missing in child | Child `.envrc` overrides after `source_up` | Reorder: put `source_up` before `export` in child |
| `op://` not resolved | Claude's shell doesn't run direnv | Use `op read` or `op run` explicitly |
| `direnv: .envrc not allowed` | File not trusted | Run `direnv allow` in that directory |
| `op run` ignores a var | Already set in shell environment | Unset first: `env -u VAR op run ...` |

## Full Chain Dump (Copy-Paste Diagnostic)

Run this block to get a complete picture of the chain, secret var names, and current state:

```bash
# 1. Print each .envrc in the chain with its path as a header
echo "=== .envrc CHAIN FROM $PWD ==="
dir="$PWD"
while [[ "$dir" != "/" && "$dir" != "$HOME/.." ]]; do
  if [[ -f "$dir/.envrc" ]]; then
    echo ""
    echo "--- $dir/.envrc ---"
    cat "$dir/.envrc"
  fi
  dir="$(dirname "$dir")"
done

# 2. For any --env-file references, print var names only (NOT values)
echo ""
echo "=== op:// VAR NAMES IN ~/.secrets (no values) ==="
grep "op://" ~/.secrets 2>/dev/null | sed 's/=.*//' || echo "(~/.secrets not found)"

# 3. Show current direnv status
echo ""
echo "=== direnv status ==="
direnv status

# 4. Show currently set vars that look like secrets (mask values)
echo ""
echo "=== LIKELY SECRET VARS IN CURRENT ENV (values masked) ==="
env | grep -E "KEY|TOKEN|SECRET|PASSWORD|API" | sed 's/=.*/=<masked>/'
```

## Reminders

- NEVER print secret values — only var names. Use `sed 's/=.*//'` or `sed 's/=.*/=<masked>/'` consistently.
- The Claude shell cannot resolve `op://` URIs. Use `op read 'op://vault/item/field'` for individual values or `op run --env-file ~/.secrets -- <cmd>` to inject into a command.
- `direnv export bash` is a safe dry run — it does not modify the current environment.
- If `~/dev/.envrc` doesn't exist, the chain is broken and any vars defined there won't be available in child projects.
- A common source of "var missing" bugs: `source_up` is called after `export VAR=...` in the child, so the parent's definition of that var wins and silently replaces the child's.
