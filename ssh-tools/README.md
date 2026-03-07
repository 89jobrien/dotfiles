# SSH Key Management Tools

Automated SSH key distribution and management across Tailscale mesh network.

## Features

### Key Sync Across Devices

Automatically distribute your SSH public key to all Tailscale devices:

```bash
# Sync default key (~/.ssh/id_ed25519.pub) to all devices
mise run ssh-sync

# Preview what would be synced
mise run ssh-sync-dry-run

# Sync a specific key
SSH_KEY=~/.ssh/work_ed25519.pub mise run ssh-sync
```

**How it works:**
1. Reads the latest Tailscale device export from `tailscale/backups/`
2. Connects to each device via SSH (using `ts-*` aliases)
3. Adds your public key to `~/.ssh/authorized_keys` (idempotent)
4. Sets correct permissions (700 for .ssh, 600 for authorized_keys)

### Smart Features

**Idempotent:**
- Won't add duplicate keys
- Safe to run multiple times
- Preserves existing authorized_keys entries

**Error Handling:**
- Skips mobile devices (Android/iOS)
- Continues on connection failures
- Shows clear status for each device

**Customization:**
```bash
# Dry run mode
DRY_RUN=1 ./ssh-tools/scripts/sync-keys.sh

# Custom key
./ssh-tools/scripts/sync-keys.sh --key ~/.ssh/custom.pub

# Via mise/just
just ssh-sync
mise run ssh-sync
```

## Use Cases

### Initial Setup

After deploying dotfiles to a new Tailscale device:

```bash
# On new device, after pulling dotfiles and generating SSH config:
git pull
mise run ts-ssh           # Generate SSH config with ts-* aliases
source ~/.zshrc           # Load new SSH config

# On your main machine:
mise run ssh-sync         # Distribute your key to all devices including new one
```

Now you can SSH to the new device without passwords.

### Key Rotation

When rotating SSH keys:

```bash
# Generate new key
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_new

# Distribute new key to all devices
SSH_KEY=~/.ssh/id_ed25519_new.pub mise run ssh-sync

# Test connections work with new key
ssh ts-device-name

# Replace old key
mv ~/.ssh/id_ed25519_new ~/.ssh/id_ed25519
mv ~/.ssh/id_ed25519_new.pub ~/.ssh/id_ed25519.pub
```

### Work vs Personal Keys

Maintain separate keys for different contexts:

```bash
# Sync personal key to personal devices
SSH_KEY=~/.ssh/personal_ed25519.pub mise run ssh-sync

# Sync work key to work devices (manually select via dry-run)
SSH_KEY=~/.ssh/work_ed25519.pub mise run ssh-sync-dry-run
```

## Requirements

- Tailscale device export CSV in `tailscale/backups/`
- Generated SSH config with `ts-*` host aliases (via `mise run ts-ssh`)
- SSH access to at least one device (bootstrap the first connection manually)

## Troubleshooting

### "No Tailscale device CSV found"

Export devices from Tailscale admin console:
1. Go to https://login.tailscale.com/admin/machines
2. Click "Export as CSV"
3. Save to `~/dotfiles/tailscale/backups/devices-YYYY-MM-DD.csv`

### "Connection failed" for all devices

Check SSH config is loaded:
```bash
grep -A 5 "ts-" ~/.ssh/config
```

If missing, regenerate and reload:
```bash
mise run ts-ssh
source ~/.zshrc
```

### Permission denied (publickey)

You may need to bootstrap the first connection manually:
1. SSH to the device using password auth
2. Manually add your public key to `~/.ssh/authorized_keys`
3. Then `mise run ssh-sync` will work for future updates

## Integration

The SSH sync tool integrates with:

- **Tailscale automation**: Uses device CSV exports
- **SSH config generation**: Uses `ts-*` host aliases
- **Task runners**: Available via mise/just commands
- **Bootstrap flow**: Can be run as part of post-bootstrap setup

## Future Enhancements

See `IDEAS.local.md` for planned features:
- Automated key rotation with backup
- Key distribution groups (work vs personal)
- Audit trail of key deployments
- Health check for key consistency across devices
