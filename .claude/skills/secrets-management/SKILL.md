---
name: secrets-management
description: Use when managing encrypted secrets, extracting SSH keys, accessing remote machines via Tailscale, or working with op/sops/age. Symptoms - sops decrypt failed, age key missing, op CLI errors, SSH auth failures, too many authentication failures, tailscale device not found, need credentials for machines or services.
---

# Secrets Management

> **Infra config:** Machine names, IPs, and credentials come from `~/.claude/infra.toml`.
> See `~/.claude/infra.toml.example` for the template. Load vars in scripts with `source ~/.claude/skills/lib/infra-load.sh`.

## Stack Overview

| Tool | Role |
|------|------|
| `age` | Encryption primitive; keys at `~/.config/sops/age/keys.txt` |
| `sops` | Encrypts/decrypts secret files using age keys |
| `op` (1Password CLI) | Credential store; backs up age key; holds SSH keys |
| Tailscale | Encrypted overlay network; machine access via `100.x.x.x` |
| SSH + 1P agent | Key-based machine auth routed through 1Password |

---

## age + sops

### Key Management

Private key: `~/.config/sops/age/keys.txt` (override with `$SOPS_AGE_KEY_FILE`)

```bash
# Generate new key
age-keygen -o ~/.config/sops/age/keys.txt

# Restore from 1Password (item: "age-key-dotfiles", vault: cli)
op item get "age-key-dotfiles" --account=$INFRA_OP_PERSONAL --fields notesPlain \
  > ~/.config/sops/age/keys.txt && chmod 600 ~/.config/sops/age/keys.txt

# Back up to 1Password
op item create --category "Secure Note" --title "age-key-dotfiles" \
  "notesPlain=$(cat ~/.config/sops/age/keys.txt)" --account=$INFRA_OP_PERSONAL
```

The dotfiles `setup-secrets.sh` auto-restores from 1Password if the key is missing during bootstrap.

### .sops.yaml

Defines which files are encrypted and with which public key:

```yaml
creation_rules:
  - path_regex: secrets/.*\.sops(\.json|\.yaml|\.env)?$
    age: age1rek84cdzedc33erq5gq5uylw3g8ln5uvs5zx9jf4c8vm865rfgcqa052ur
  - path_regex: \.env\.sops(\.json|\.yaml)?$
    age: age1rek84cdzedc33erq5gq5uylw3g8ln5uvs5zx9jf4c8vm865rfgcqa052ur
```

The age public key above is the dotfiles repo key. Never commit the private key.

### sops Operations

```bash
# Decrypt to stdout
sops --decrypt secrets/bootstrap.env.sops

# Decrypt to file
sops --decrypt secrets/bootstrap.env.sops > ~/.config/dev-bootstrap/secrets.env
chmod 600 ~/.config/dev-bootstrap/secrets.env

# Encrypt a new file (uses .sops.yaml rules)
sops --encrypt secrets/bootstrap.env > secrets/bootstrap.env.sops

# Edit in-place (decrypt → edit → re-encrypt atomically)
sops secrets/bootstrap.env.sops
```

Decrypted secrets land at: `~/.config/dev-bootstrap/secrets.env`

---

## 1Password CLI

### Accounts

| Account | Use |
|---------|-----|
| `$INFRA_OP_PERSONAL` | Personal — SSH keys, infra, age key |
| `toptal.1password.com` | Work credentials |

**Always specify `--account=$INFRA_OP_PERSONAL` for infra/machine credentials.**

### Vaults

| Vault | Contents |
|-------|----------|
| `Personal` | General credentials, some SSH keys |
| `cli` | SSH keys, API keys, `age-key-dotfiles`, programmatic items |

Items may be in either vault. Search without vault filter if not found:
```bash
op item list --account=$INFRA_OP_PERSONAL
```

### Known Items

| Item | Vault | Use |
|------|-------|-----|
| `age-key-dotfiles` | `cli` | age private key for dotfiles sops encryption |
| `rentamac` | `Personal` | mac-mini SSH key (secure note) |
| `Rent a Mac` | `Personal` | mac-mini login credentials |

### Common op Operations

```bash
# List items
op item list --account=$INFRA_OP_PERSONAL

# Get full item as JSON
op item get "<name>" --account=$INFRA_OP_PERSONAL --format=json

# Get specific field
op item get "<name>" --account=$INFRA_OP_PERSONAL --fields <field>

# Inject secrets into a command's environment
op run --env-file .env -- <command>

# Find item by keyword (titles are inconsistent)
op item list --account=$INFRA_OP_PERSONAL --format=json | python3 -c "
import sys, json
for i in json.load(sys.stdin):
    if 'keyword' in i.get('title','').lower():
        print(i['title'], i.get('id',''))
"
```

### SSH Key Extraction

`op read` outputs SSH keys in a format `ssh -i` rejects ("invalid format"). **Extract via JSON with `--reveal`:**

```bash
# ❌ WRONG — produces invalid key format
op read "op://vault/item/private key" > /tmp/key

# ✅ CORRECT
op item get "<item-id>" --account=$INFRA_OP_PERSONAL --reveal --format=json | python3 -c "
import sys, json
item = json.load(sys.stdin)
for f in item.get('fields', []):
    if f.get('label') == 'private key':
        print(f.get('value', ''))
" > /tmp/key
chmod 600 /tmp/key

# Always clean up after use
rm -f /tmp/key
```

---

## SSH + 1Password Agent

Global SSH config routes all connections through 1Password agent:
```
Host *
    IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
```

**"Too many authentication failures"**: 1P agent offers all stored keys; servers reject after N attempts. Fix — bypass agent and specify key directly:

```bash
ssh -o IdentitiesOnly=yes -o IdentityAgent=none -i /path/to/key user@host "command"
```

Password auth via `sshpass`:
```bash
sshpass -p 'password' ssh -o IdentitiesOnly=yes -o IdentityAgent=none user@host "command"

# With sudo over SSH
sshpass -p 'pw' ssh -o IdentitiesOnly=yes -o IdentityAgent=none user@host "sudo -S command" <<< 'pw'
```

---

## Tailscale

### CLI

```bash
# View all devices
tailscale status

# Fallback if not in PATH on remote macOS
/Applications/Tailscale.app/Contents/MacOS/Tailscale status

# Rename a device (run ON that device)
tailscale set --hostname=new-name

# Get tailnet name / self info
tailscale status --json | python3 -c "
import sys, json; d=json.load(sys.stdin); print(d.get('MagicDNSSuffix',''))"
```

**Note:** `tailscale ssh` is NOT available on App Store builds. Use regular `ssh` instead.

### Known Machines

| Machine | Tailscale IP | SSH User | Auth | 1P Item |
|---------|-------------|----------|------|---------|
| `$INFRA_MAC_MINI_HOST` | (see infra.toml) | `$INFRA_MAC_MINI_USER` | SSH key (1P agent) | "rentamac" / "Rent a Mac" |
| `$INFRA_VPS_HOST` | `$INFRA_VPS_IP` | `$INFRA_VPS_USER` | Password | `$INFRA_VPS_OP_ITEM` |
| `$INFRA_DEV_HOST` | `$INFRA_DEV_IP` | `$INFRA_DEV_USER` | Local | N/A |
| `$INFRA_LAB_HOST` | not yet on network | — | — | — |

### Connecting

```bash
source ~/.claude/skills/lib/infra-load.sh

# mac-mini
ssh $INFRA_MAC_MINI_USER@$INFRA_MAC_MINI_ADDR "command"

# VPS (password auth)
sshpass -p "$(op item get $INFRA_VPS_OP_ITEM --account=$INFRA_OP_PERSONAL --fields password --reveal)" \
  ssh -o IdentitiesOnly=yes -o IdentityAgent=none $INFRA_VPS_USER@$INFRA_VPS_IP "command"
```

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| `sops` decrypt fails | Verify `~/.config/sops/age/keys.txt` exists; restore from 1P if missing |
| Age key missing on new machine | `op item get "age-key-dotfiles" --fields notesPlain > ~/.config/sops/age/keys.txt` |
| `op read` SSH key invalid format | Use `op item get --reveal --format=json` + python extraction |
| Wrong 1P account | Always `--account=$INFRA_OP_PERSONAL` for personal/infra |
| SSH "too many auth failures" | `-o IdentitiesOnly=yes -o IdentityAgent=none -i /key` |
| `tailscale ssh` not working on macOS | App Store build lacks it — use regular `ssh` |
| Item not found by name | Titles are inconsistent — search broadly with `op item list` |
| Bare `tailscale` not in PATH on remote | Use full app path as fallback |
| Forgot to delete temp key file | `rm -f /tmp/key` immediately after use |
| `sudo` over SSH hangs | Use `sudo -S command <<< 'password'` or avoid sudo |
