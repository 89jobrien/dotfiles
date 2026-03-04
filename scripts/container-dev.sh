#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="containers"

PROFILE="${COLIMA_PROFILE:-dev}"
CPUS="${COLIMA_CPUS:-4}"
MEMORY_GB="${COLIMA_MEMORY_GB:-6}"
DISK_GB="${COLIMA_DISK_GB:-60}"
K3D_CLUSTER="${K3D_CLUSTER_NAME:-dev}"
KIND_CLUSTER="${KIND_CLUSTER_NAME:-dev}"

colima_start() {
  require_cmd colima
  if colima status --profile "${PROFILE}" >/dev/null 2>&1; then
    log_skip "Colima profile '${PROFILE}' already running"
    return 0
  fi
  log "starting Colima profile '${PROFILE}' (${CPUS} CPU, ${MEMORY_GB}GiB RAM, ${DISK_GB}GiB disk)..."
  # k3d expects a Docker daemon, so default to docker runtime.
  if ! colima start --profile "${PROFILE}" --cpu "${CPUS}" --memory "${MEMORY_GB}" --disk "${DISK_GB}" --runtime docker; then
    log_err "Colima start failed"
    log "if this profile was previously created with containerd, delete data and retry:"
    log "  colima delete --profile \"${PROFILE}\" --data -f"
    log "  scripts/container-dev.sh start"
    if [[ "${COLIMA_RESET_DATA_ON_RUNTIME_MISMATCH:-0}" == "1" ]]; then
      log_warn "COLIMA_RESET_DATA_ON_RUNTIME_MISMATCH=1 set; deleting profile data and retrying..."
      colima delete --profile "${PROFILE}" --data -f
      colima start --profile "${PROFILE}" --cpu "${CPUS}" --memory "${MEMORY_GB}" --disk "${DISK_GB}" --runtime docker
    else
      exit 1
    fi
  fi
}

colima_stop() {
  require_cmd colima
  if ! colima status --profile "${PROFILE}" >/dev/null 2>&1; then
    log_skip "Colima profile '${PROFILE}' is not running"
    return 0
  fi
  log "stopping Colima profile '${PROFILE}'..."
  colima stop --profile "${PROFILE}"
}

status() {
  log "runtime status"
  if has_cmd colima; then
    colima status --profile "${PROFILE}" || true
  fi
  if has_cmd docker; then
    docker version --format '{{.Server.Version}}' 2>/dev/null | awk '{print "[containers] docker server " $0}' || log_warn "docker server unavailable"
  fi
  if has_cmd kubectl; then
    kubectl config current-context 2>/dev/null | awk '{print "[containers] kube context " $0}' || log_warn "kubectl context unavailable"
  fi
}

k3d_up() {
  require_cmd k3d
  colima_start
  if k3d cluster list | awk 'NR>1 {print $1}' | grep -qx "${K3D_CLUSTER}"; then
    log_skip "k3d cluster '${K3D_CLUSTER}' already exists"
    return 0
  fi
  log "creating k3d cluster '${K3D_CLUSTER}'..."
  k3d cluster create "${K3D_CLUSTER}" --wait
}

k3d_down() {
  require_cmd k3d
  if ! k3d cluster list | awk 'NR>1 {print $1}' | grep -qx "${K3D_CLUSTER}"; then
    log_skip "k3d cluster '${K3D_CLUSTER}' not found"
    return 0
  fi
  log "deleting k3d cluster '${K3D_CLUSTER}'..."
  k3d cluster delete "${K3D_CLUSTER}"
}

kind_up() {
  require_cmd kind
  colima_start
  if kind get clusters | grep -qx "${KIND_CLUSTER}"; then
    log_skip "kind cluster '${KIND_CLUSTER}' already exists"
    return 0
  fi
  log "creating kind cluster '${KIND_CLUSTER}'..."
  kind create cluster --name "${KIND_CLUSTER}"
}

kind_down() {
  require_cmd kind
  if ! kind get clusters | grep -qx "${KIND_CLUSTER}"; then
    log_skip "kind cluster '${KIND_CLUSTER}' not found"
    return 0
  fi
  log "deleting kind cluster '${KIND_CLUSTER}'..."
  kind delete cluster --name "${KIND_CLUSTER}"
}

tilt_up() {
  require_cmd tilt
  log "starting Tilt..."
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
