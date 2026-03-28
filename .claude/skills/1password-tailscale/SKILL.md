---
name: 1password-tailscale
description: Use when SSHing into remote machines, looking up credentials, renaming Tailscale devices, or accessing services on the tailnet. Symptoms - SSH auth failures, too many authentication failures, command not found tailscale, need to find credentials for remote machines.
---

# 1Password + Tailscale System

## Overview

Joe's infrastructure uses 1Password CLI (`op`) for credential management and Tailscale for networking between machines. SSH is configured to use the 1Password agent, which introduces specific quirks that must be handled correctly.

## Quick Reference

### Tailscale CLI

The `tailscale` command is available two ways:

| Method | Path | Notes |
|--------|------|-------|
| App Store app | `/Applications/Tailscale.app/Contents/MacOS/Tailscale` | Always available on macOS machines. `tailscale ssh` NOT available on App Store builds. |
| Homebrew CLI | `tailscale` (in PATH) | Installed on m5-max. Provides `tailscale ssh` if using standalone build. |

**QUIRK:** The bare `tailscale` command may not be in PATH on remote macOS machines. Always try the full app path as fallback:
```bash
# Try short form first, fall back to app path
tailscale status 2>/dev/null || /Applications/Tailscale.app/Contents/MacOS/Tailscale status
```

### Common Tailscale Operations

```bash
# View all devices
tailscale status

# Rename a device (run ON that device)
tailscale set --hostname=new-name

# Get detailed info (tailnet name, self info)
tailscale status --json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('MagicDNSSuffix',''))"
```

## 1Password CLI

### Accounts

Joe has two 1Password accounts:

| Account | Email | Use |
|---------|-------|-----|
| `my.1password.com` | joeobrien516@gmail.com | Personal — SSH keys, machine credentials, personal services |
| `toptal.1password.com` | joseph.obrien@toptal.com | Work — work-related credentials |

**IMPORTANT:** Always specify `--account=my.1password.com` for infrastructure/machine credentials. The default account may be the work one.

### Vaults (Personal Account)

| Vault | Contents |
|-------|----------|
| `Personal` | General credentials, some SSH keys |
| `cli` | SSH keys, API credentials, programmatic access items |

**QUIRK:** Items may be in either vault. If you can't find an item, search without vault filter first:
```bash
op item list --account=my.1password.com
```

Then check which vault it's in:
```bash
op item get "<item-name>" --account=my.1password.com --format=json | python3 -c "import sys,json; print(json.load(sys.stdin).get('vault',{}).get('name',''))"
```

### Finding Credentials

Search by keyword — item titles don't always match device names:
```bash
op item list --account=my.1password.com --format=json | python3 -c "
import sys,json
items=json.load(sys.stdin)
for i in items:
    title = i.get('title','').lower()
    if any(k in title for k in ['keyword1','keyword2']):
        print(f\"{i['title']} ({i.get('category','')}) [{i.get('id','')}]\")
"
```

### Extracting SSH Private Keys

**CRITICAL QUIRK:** `op read` outputs SSH keys in a format that `ssh -i` rejects ("invalid format" or "Load key: invalid format"). You MUST extract keys via JSON:

```bash
# ❌ WRONG — produces invalid key format
op read "op://vault/item/private key" > /tmp/key

# ✅ CORRECT — extract via JSON with --reveal
op item get "<item-id>" --account=my.1password.com --reveal --format=json | python3 -c "
import sys, json
item = json.load(sys.stdin)
for f in item.get('fields', []):
    if f.get('label') == 'private key':
        print(f.get('value', ''))
" > /tmp/key
chmod 600 /tmp/key
```

**Always clean up temp key files after use:**
```bash
rm -f /tmp/key
```

## SSH with 1Password Agent

### The "Too Many Authentication Failures" Problem

The 1Password SSH agent offers ALL stored SSH keys to the server. If you have many keys (Joe has 5+), the server rejects the connection before finding the right one.

**Fix:** Bypass the 1Password agent and specify the key directly:
```bash
ssh -o IdentitiesOnly=yes -o IdentityAgent=none -i /path/to/extracted/key user@host "command"
```

### SSH Config

The global SSH config routes all connections through 1Password:
```
Host *
    IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
```

This is why `-o IdentityAgent=none` is needed when using a specific key file.

### Password-Based SSH

For machines that use password auth, use `sshpass` (installed via Homebrew):
```bash
sshpass -p 'password' ssh -o IdentitiesOnly=yes -o IdentityAgent=none user@host "command"
```

For commands requiring sudo:
```bash
sshpass -p 'password' ssh -o IdentitiesOnly=yes -o IdentityAgent=none user@host "sudo -S command" <<< 'password'
```

## Known 1Password Items (Dotfiles)

| Item | Vault | Use |
|------|-------|-----|
| `age-key-dotfiles` | `cli` | age private key for sops secrets in the dotfiles repo — auto-restored to `~/.config/sops/age/keys.txt` by `setup-secrets.sh` if missing |

To manually restore or back up the age key:
```bash
# Restore key from 1Password
op item get "age-key-dotfiles" --account=my.1password.com --fields notesPlain > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt

# Save updated key to 1Password (creates new item)
op item create --category "Secure Note" --title "age-key-dotfiles" \
  "notesPlain=$(cat ~/.config/sops/age/keys.txt)" --account=my.1password.com
```

## Machine Credentials

### Known Machines

| Machine | Tailscale IP | SSH User | Auth Method | 1Password Item |
|---------|-------------|----------|-------------|----------------|
| mac-mini | 100.111.235.46 | rentamac | SSH key (1Password agent) | "rentamac" (secure note), "Rent a Mac" (login) |
| jobrien-vm | 100.105.75.7 | dev | Password | "jobrien-vm" (login, Personal vault) |
| m5-max | 100.105.148.117 | joe | Local | N/A |

### Connecting to Each Machine

**mac-mini:**
```bash
ssh rentamac@100.111.235.46 "command"
# Or via tailnet DNS:
ssh rentamac@mac-mini.taila01bd5.ts.net "command"
```

**jobrien-vm:**
```bash
sshpass -p "$(op item get jobrien-vm --account=my.1password.com --fields password --reveal)" ssh -o IdentitiesOnly=yes -o IdentityAgent=none -o PreferredAuthentications=password dev@100.105.75.7 "command"
```

## op run on m5-max: Shell Env Has Mixed op:// References

**CRITICAL:** The shell environment on m5-max has many `op://` references already set (ANTHROPIC_API_KEY, OPENAI_API_KEY, FIRECRAWL_API_KEY, etc. — all pointing to `Personal` or `cli` vaults in `my.1password.com`). When you run `op run --account=toptal.1password.com`, it tries to resolve ALL `op://` references in the current environment, including those personal vault ones — and fails.

**Rule:** Always use `--account=my.1password.com` with `--env-file=~/.secrets`. Never use the toptal account from an interactive shell — the shell env and `~/.secrets` only reference personal vaults.

`~/.secrets` is the canonical op:// env file — all `cli` and `Personal` vault references, no work vault refs.

```bash
# ✅ CORRECT — personal account + ~/.secrets
op run --account=my.1password.com --env-file=~/.secrets -- <command>

# ❌ WRONG — toptal account can't resolve op://Personal/... or op://cli/... refs
op run --account=toptal.1password.com --env-file some.env -- <command>
```

If a tool has its own `.env` with `op://Employee/...` (toptal vaults), ignore it — the equivalent key is already in `~/.secrets` pointing to the personal vault.

## direnv + op run: How Shell Env Is Loaded

The shell env on m5-max is loaded by direnv via `/Users/joe/dev/.envrc` (and per-project `.envrc` files that call `source_up`). The parent `.envrc` runs `op run --account=my.1password.com --env-file=~/.secrets -- env` and exports all resolved secrets into the shell.

**`~/.secrets` is the canonical secret file** — op:// references for all CLI/Personal vault keys. When you need a secret available in shell (and therefore in `mise run`, `uv run`, etc.), it must be in `~/.secrets`.

### ANTHROPIC_API_KEY — canonical reference

```
ANTHROPIC_API_KEY="op://Personal/vps-anthropic-api/ANTHROPIC_API_KEY"
```

**QUIRK:** The `cli` vault has an item called `Anthropic API Key` whose `credential` field contains `sk-ant-oat01-...` — an **OAuth token, not an API key**. This resolves successfully via `op run` but is rejected by the Anthropic API with "Invalid API key". Always use the `Personal/vps-anthropic-api` item.

### Reloading after changing `~/.secrets`

After editing `~/.secrets`, run `direnv reload` (or `cd` out and back in) to re-export the new values:

```bash
direnv reload
# or
cd .. && cd -
```

### If `mise run` doesn't see env vars

`mise run` inherits the shell environment, so direnv must be loaded in the calling shell. If running from a shell without direnv (e.g., a CI script, a nushell subprocess, or a `run_in_background` Bash tool call), source the env manually:

```bash
eval "$(op run --account=my.1password.com --env-file=~/.secrets -- env | grep -E '^(ANTHROPIC|OPENAI|GEMINI)' | sed 's/^/export /')"
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Using bare `tailscale` on remote macOS | Use `/Applications/Tailscale.app/Contents/MacOS/Tailscale` |
| SSH failing with "too many auth failures" | Add `-o IdentitiesOnly=yes -o IdentityAgent=none -i /path/to/key` |
| `op read` for SSH keys gives invalid format | Use `op item get --reveal --format=json` and extract via python |
| Searching wrong 1Password account | Always specify `--account=my.1password.com` for infra |
| Assuming item title matches device name | Search broadly, then filter — titles are inconsistent |
| `tailscale ssh` on macOS App Store build | Not available — use regular `ssh` instead |
| Forgetting to clean up temp key files | Always `rm -f /tmp/keyfile` after use |
| `sudo` over SSH without TTY | Use `sudo -S command <<< 'password'` or avoid sudo when possible |
| `op run --account=toptal` from interactive shell | Shell has `op://Personal/...` env vars; use `--account=my.1password.com` instead |
| `op://cli/Anthropic API Key/credential` | Returns OAuth token (`oat01`), not API key — use `op://Personal/vps-anthropic-api/ANTHROPIC_API_KEY` |
| env vars missing in `mise run` | direnv must be loaded in the calling shell; check with `direnv status` |
