#!/usr/bin/env bash
set -euo pipefail

PROFILE="${COLIMA_PROFILE:-dev}"
CPUS="${COLIMA_CPUS:-4}"
MEMORY_GB="${COLIMA_MEMORY_GB:-6}"
DISK_GB="${COLIMA_DISK_GB:-60}"
K3D_CLUSTER="${K3D_CLUSTER_NAME:-dev}"
KIND_CLUSTER="${KIND_CLUSTER_NAME:-dev}"

log() {
  if command -v gum >/dev/null 2>&1 && [[ -t 1 ]]; then
    gum style --foreground 212 "[containers] $*"
  else
    printf '[containers] %s\n' "$*"
  fi
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "Missing required command: $1"
    exit 1
  fi
}

colima_start() {
  need_cmd colima
  if colima status --profile "${PROFILE}" >/dev/null 2>&1; then
    log "Colima profile '${PROFILE}' already running."
    return 0
  fi
  log "Starting Colima profile '${PROFILE}' (${CPUS} CPU, ${MEMORY_GB}GiB RAM, ${DISK_GB}GiB disk)..."
  # k3d expects a Docker daemon, so default to docker runtime.
  if ! colima start --profile "${PROFILE}" --cpu "${CPUS}" --memory "${MEMORY_GB}" --disk "${DISK_GB}" --runtime docker; then
    log "Colima start failed."
    log "If this profile was previously created with containerd, delete data and retry:"
    log "  colima delete --profile \"${PROFILE}\" --data -f"
    log "  scripts/container-dev.sh start"
    if [[ "${COLIMA_RESET_DATA_ON_RUNTIME_MISMATCH:-0}" == "1" ]]; then
      log "COLIMA_RESET_DATA_ON_RUNTIME_MISMATCH=1 set; deleting profile data and retrying..."
      colima delete --profile "${PROFILE}" --data -f
      colima start --profile "${PROFILE}" --cpu "${CPUS}" --memory "${MEMORY_GB}" --disk "${DISK_GB}" --runtime docker
    else
      exit 1
    fi
  fi
}

colima_stop() {
  need_cmd colima
  if ! colima status --profile "${PROFILE}" >/dev/null 2>&1; then
    log "Colima profile '${PROFILE}' is not running."
    return 0
  fi
  log "Stopping Colima profile '${PROFILE}'..."
  colima stop --profile "${PROFILE}"
}

status() {
  log "Runtime status"
  if command -v colima >/dev/null 2>&1; then
    colima status --profile "${PROFILE}" || true
  fi
  if command -v docker >/dev/null 2>&1; then
    docker version --format '{{.Server.Version}}' 2>/dev/null | awk '{print "[containers] docker server " $0}' || log "docker server unavailable"
  fi
  if command -v kubectl >/dev/null 2>&1; then
    kubectl config current-context 2>/dev/null | awk '{print "[containers] kube context " $0}' || log "kubectl context unavailable"
  fi
}

k3d_up() {
  need_cmd k3d
  colima_start
  if k3d cluster list | awk 'NR>1 {print $1}' | grep -qx "${K3D_CLUSTER}"; then
    log "k3d cluster '${K3D_CLUSTER}' already exists."
    return 0
  fi
  log "Creating k3d cluster '${K3D_CLUSTER}'..."
  k3d cluster create "${K3D_CLUSTER}" --wait
}

k3d_down() {
  need_cmd k3d
  if ! k3d cluster list | awk 'NR>1 {print $1}' | grep -qx "${K3D_CLUSTER}"; then
    log "k3d cluster '${K3D_CLUSTER}' not found."
    return 0
  fi
  log "Deleting k3d cluster '${K3D_CLUSTER}'..."
  k3d cluster delete "${K3D_CLUSTER}"
}

kind_up() {
  need_cmd kind
  colima_start
  if kind get clusters | grep -qx "${KIND_CLUSTER}"; then
    log "kind cluster '${KIND_CLUSTER}' already exists."
    return 0
  fi
  log "Creating kind cluster '${KIND_CLUSTER}'..."
  kind create cluster --name "${KIND_CLUSTER}"
}

kind_down() {
  need_cmd kind
  if ! kind get clusters | grep -qx "${KIND_CLUSTER}"; then
    log "kind cluster '${KIND_CLUSTER}' not found."
    return 0
  fi
  log "Deleting kind cluster '${KIND_CLUSTER}'..."
  kind delete cluster --name "${KIND_CLUSTER}"
}

tilt_up() {
  need_cmd tilt
  log "Starting Tilt..."
  tilt up
}

case "${1:-status}" in
  start) colima_start ;;
  stop) colima_stop ;;
  status) status ;;
  k3d-up) k3d_up ;;
  k3d-down) k3d_down ;;
  kind-up) kind_up ;;
  kind-down) kind_down ;;
  tilt-up) tilt_up ;;
  *)
    cat <<'EOF'
Usage: scripts/container-dev.sh <command>

Commands:
  start      Start Colima runtime
  stop       Stop Colima runtime
  status     Show runtime and kube context
  k3d-up     Create local k3d cluster
  k3d-down   Delete local k3d cluster
  kind-up    Create local kind cluster
  kind-down  Delete local kind cluster
  tilt-up    Start Tilt from current directory
EOF
    exit 1
    ;;
esac
