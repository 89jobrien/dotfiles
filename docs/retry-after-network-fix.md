# Retry After Install/Runtime Fixes

Run from `~/dotfiles`:

```bash
cd ~/dotfiles

# 1) Rust tools (optional)
# (none required)

# 2) Recreate Colima profile with Docker runtime (required by k3d)
./scripts/container-dev.sh stop || true
colima delete --profile dev --data -f || true
./scripts/container-dev.sh start
docker info --format '{{.ServerVersion}}'

# 3) Bring up local cluster
./scripts/container-dev.sh k3d-up

# 4) Validate all required tools
make doctor
```
