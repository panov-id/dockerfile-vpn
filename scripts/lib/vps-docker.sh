#!/usr/bin/env bash
## Docker on VPS (Debian/Ubuntu). Used by launchpad, vps-deploy-stand, server-setup-wizard.

DOCKER_COMPOSE_PLUGIN_VERSION="${DOCKER_COMPOSE_PLUGIN_VERSION:-2.29.7}"

vps_run_privileged() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

vps_is_debian_or_ubuntu() {
  if [[ ! -f /etc/os-release ]]; then
    return 1
  fi
  # shellcheck source=/dev/null
  source /etc/os-release
  case "${ID:-}" in
    debian | ubuntu) return 0 ;;
    *) return 1 ;;
  esac
}

vps_docker_compose_is_available() {
  command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1
}

vps_install_compose_plugin_from_github() {
  local architecture_identifier
  architecture_identifier="$(uname -m)"
  local compose_architecture_suffix
  case "${architecture_identifier}" in
    x86_64) compose_architecture_suffix="x86_64" ;;
    aarch64 | arm64) compose_architecture_suffix="aarch64" ;;
    *)
      echo "Unsupported architecture for Compose plugin: ${architecture_identifier}" >&2
      return 1
      ;;
  esac
  local plugin_directory="/usr/local/lib/docker/cli-plugins"
  local temporary_compose_binary="/tmp/docker-compose-linux-${compose_architecture_suffix}"
  local download_url="https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_PLUGIN_VERSION}/docker-compose-linux-${compose_architecture_suffix}"

  echo "Installing Docker Compose v${DOCKER_COMPOSE_PLUGIN_VERSION} from GitHub (${compose_architecture_suffix}) …"
  vps_run_privileged mkdir -p "${plugin_directory}"
  curl -fsSL "${download_url}" -o "${temporary_compose_binary}"
  vps_run_privileged install -m 755 "${temporary_compose_binary}" "${plugin_directory}/docker-compose"
  rm -f "${temporary_compose_binary}"
}

vps_install_docker_via_apt() {
  echo "Installing Docker Engine and Compose (apt + upstream Compose plugin if needed) …"
  export DEBIAN_FRONTEND=noninteractive
  vps_run_privileged apt-get update -y
  vps_run_privileged apt-get install -y docker.io ca-certificates curl

  if ! vps_run_privileged apt-get install -y docker-compose-plugin 2>/dev/null; then
    echo "Package docker-compose-plugin not in apt — using Compose binary from GitHub."
    vps_install_compose_plugin_from_github
  fi

  if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
    vps_run_privileged systemctl enable --now docker || true
  fi
}

vps_ensure_unix_user_in_docker_group() {
  local deploy_unix_user="${1:?}"
  if [[ "${deploy_unix_user}" == root ]] || ! id "${deploy_unix_user}" >/dev/null 2>&1; then
    return 0
  fi
  vps_run_privileged usermod -aG docker "${deploy_unix_user}"
  echo "User '${deploy_unix_user}' added to group docker (re-login or newgrp docker if needed)."
}

# Idempotent: install if missing; optional deploy user for docker group (not required for root).
vps_ensure_docker_installed() {
  local deploy_unix_user="${1:-}"

  if vps_docker_compose_is_available; then
    echo "Docker Compose is already available."
  else
    if ! vps_is_debian_or_ubuntu; then
      echo "Automatic Docker install supports Debian/Ubuntu only (install Docker manually)." >&2
      return 1
    fi
    vps_install_docker_via_apt
  fi

  if [[ -n "${deploy_unix_user}" ]]; then
    vps_ensure_unix_user_in_docker_group "${deploy_unix_user}"
  fi

  if ! vps_docker_compose_is_available; then
    echo "docker compose is still not available after install." >&2
    return 1
  fi
  return 0
}
