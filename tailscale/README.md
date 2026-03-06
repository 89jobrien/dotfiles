# Tailscale Device Management

Automated Tailscale device inventory management, SSH config generation, and key expiry monitoring.

## Quick Start

```bash
# List all devices
mise run ts-devices

# Generate SSH config
mise run ts-ssh

# Check expiry dates
mise run ts-expiry

# Import new device export
mise run ts-refresh ~/Downloads/your-export.csv
```

## Directory Structure

```
tailscale/
├── backups/              # Device CSV snapshots (gitignored)
├── scripts/              # Automation scripts
│   ├── parse-devices.sh      # Device info parser
│   ├── generate-ssh-config.sh # SSH config generator
│   ├── check-expiry.sh        # Expiry monitor
│   └── refresh-devices.sh     # Import new exports
└── ssh-config.generated  # Auto-generated SSH config (gitignored)
```

## Scripts

### `parse-devices.sh`

Extract and query device information from CSV exports.

```bash
# List all devices with IPs and expiry
./tailscale/scripts/parse-devices.sh list

# Get device names only
./tailscale/scripts/parse-devices.sh names

# Get IP for specific device
./tailscale/scripts/parse-devices.sh ip jobrien

# Get domain for specific device
./tailscale/scripts/parse-devices.sh domain josephs-macbook-air
```

### `generate-ssh-config.sh`

Generate SSH config entries for all Tailscale devices (excluding mobile).

```bash
./tailscale/scripts/generate-ssh-config.sh
```

Creates `tailscale/ssh-config.generated` with entries like:

```ssh
Host ts-jobrien
    HostName 100.105.75.7
    User joe
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
```

**To use:** Add to `~/.ssh/config`:

```ssh
Include ~/.dotfiles/tailscale/ssh-config.generated
```

Then connect with: `ssh ts-jobrien`

### `check-expiry.sh`

Monitor device key expiry dates and warn before expiration.

```bash
# Check with default 30-day warning threshold
./tailscale/scripts/check-expiry.sh

# Custom warning threshold (60 days)
./tailscale/scripts/check-expiry.sh 60
```

Output:
- ✅ Green: All keys valid >30 days
- ⚠️  Yellow: Keys expiring within threshold
- ❌ Red: Expired keys

### `refresh-devices.sh`

Import new Tailscale device export and regenerate configs.

```bash
./tailscale/scripts/refresh-devices.sh ~/Downloads/your-export.csv
```

**Steps to refresh:**
1. Go to https://login.tailscale.com/admin/machines
2. Click "..." menu → "Export to CSV"
3. Run: `mise run ts-refresh ~/Downloads/your-export.csv`

This will:
- Copy CSV to `backups/` with timestamp
- Regenerate SSH config
- Check expiry dates

## Task Runners

Available in `mise`, `just`, and `make`:

| mise | just | Description |
|------|------|-------------|
| `mise run ts-devices` | `just ts-devices` | List devices |
| `mise run ts-ssh` | `just ts-ssh` | Generate SSH config |
| `mise run ts-expiry` | `just ts-expiry` | Check expiry |
| `mise run ts-refresh` | `just ts-refresh <csv>` | Import new export |

## Security

Device exports contain sensitive network topology information:
- Device IDs
- Tailscale IPs
- Network structure

**Protected by:**
- `.gitignore` excludes `backups/` and `ssh-config.generated`
- Recommend encrypting with `sops` if needed in version control
- CSVs remain local-only by default

## Automation Ideas

### Daily Expiry Check

Add to crontab:

```bash
0 9 * * * cd ~/.dotfiles && ./tailscale/scripts/check-expiry.sh
```

### SSH Config Auto-Update

Regenerate SSH config on device changes:

```bash
# In a post-import hook
./tailscale/scripts/refresh-devices.sh "$1" && \
  ./tailscale/scripts/generate-ssh-config.sh
```

### Integration with dotfiles bootstrap

Add to `scripts/post-bootstrap.local.sh`:

```bash
# Auto-generate Tailscale SSH config if data exists
if [[ -d ~/.dotfiles/tailscale/backups ]] && \
   ls ~/.dotfiles/tailscale/backups/devices-*.csv >/dev/null 2>&1; then
    ~/.dotfiles/tailscale/scripts/generate-ssh-config.sh
fi
```

## Troubleshooting

**Q: No devices found**
```bash
# Check backup directory
ls -la tailscale/backups/

# Import fresh export
mise run ts-refresh ~/Downloads/your-export.csv
```

**Q: SSH config not working**
```bash
# Verify Include is in ~/.ssh/config
grep -i "tailscale" ~/.ssh/config

# Regenerate
mise run ts-ssh
```

**Q: Date parsing errors**
```bash
# Install GNU date (macOS)
brew install coreutils

# Scripts automatically use gdate if available
```

## CSV Format

Expected columns from Tailscale export:
1. Device name
2. Device ID
3. Managed by
4. Creator
5. OS
6. OS Version
7. Domain
8. Tailscale version
9. Tags
10. Created
11. Last seen
12. Key expiry
13. Tailscale IPs
14. Endpoints
15. (additional fields)

Scripts parse via `IFS=','` and handle quoted values.
