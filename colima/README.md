# Colima: No-Fuss Docker Alternative

Seamless Docker experience without Docker Desktop. Colima auto-starts when you run Docker commands, with smart cross-machine configuration.

## Features

### 1. Auto-Start on Demand

Docker and docker-compose commands automatically start Colima if it's not running:

```bash
docker ps           # Colima starts automatically if needed
docker-compose up   # Works seamlessly
```

### 2. Smart Socket Detection

Works across different machines and profile configurations:
- Prefers `~/.colima/dev/docker.sock` (dev profile)
- Falls back to `~/.config/colima/default/docker.sock` (default profile)

### 3. Sensible Defaults

Default profile configuration:
- **Profile**: `dev`
- **CPUs**: 4
- **Memory**: 6GB
- **Disk**: 60GB
- **Runtime**: Docker

Override via environment variables:
```bash
export COLIMA_PROFILE=work
export COLIMA_CPUS=8
export COLIMA_MEMORY_GB=12
```

## Quick Start

### Manual Control

```bash
# Start (auto-configured)
colima-start

# Stop
colima-stop

# Restart
colima-restart

# Check status
colima-status
```

### Docker Aliases

```bash
dps                # docker ps
dpsa               # docker ps -a
di                 # docker images
dstop <container>  # docker stop
drm <container>    # docker rm
drmi <image>       # docker rmi
drmif <image>      # docker rmi -f (force)
```

## Optional: Start on Login

For users who want Colima always available (no auto-start delay):

```bash
# Enable auto-start at login
./scripts/enable-autostart.sh

# Disable auto-start
./scripts/disable-autostart.sh
```

This installs a LaunchAgent that starts Colima automatically when you log in.

## Task Runner Integration

```bash
# Via mise
mise run container-start   # Start Colima
mise run container-stop    # Stop Colima
mise run container-status  # Show status

# Via just
just container-start
just container-stop
just container-status
```

## Troubleshooting

### Colima won't start

```bash
# Delete profile data and recreate
colima delete --profile dev --data -f
colima-start
```

### Wrong socket path

Check which socket is active:
```bash
echo $DOCKER_HOST
ls -la ~/.colima/*/docker.sock
```

### Docker commands hang

```bash
# Restart Colima
colima-restart

# Or fully reset
colima stop --profile dev
colima delete --profile dev --data -f
colima-start
```

## How It Works

The `.zshrc` configuration:
1. **Socket detection**: Scans for active Colima sockets and sets `DOCKER_HOST`
2. **Command wrappers**: `docker()` and `docker-compose()` functions check Colima status
3. **Auto-start**: Starts Colima silently if not running (4-5 second delay first time)
4. **Cross-machine**: Socket detection works on any machine with any profile

## Migration from Docker Desktop

1. Uninstall Docker Desktop
2. Install via dotfiles: `brew install colima docker docker-compose`
3. Source the new `.zshrc`: `source ~/.zshrc`
4. Run any Docker command: `docker ps` (auto-starts Colima)

No configuration needed. Just works.
