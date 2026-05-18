#!/usr/bin/env bash
## Run on the VPS after you cloned this repo (Git is enough to start).
## Interactive: optional fresh clone path, install Docker on Debian/Ubuntu, seed/update .env,
## optional first `docker compose up`. Prints the absolute DEPLOY_DIRECTORY for GitHub Actions.
##
## Typical flow:
##   git clone git@github.com:panov-id/dockerfile-vpn.git
##   cd dockerfile-vpn
##   ./scripts/server-setup-wizard.sh
##
## Then configure GitHub Environment variable DEPLOY_DIRECTORY to the printed path and publish a Release.

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_directory}/.." && pwd)"

print_separator() {
  printf '%s\n' "────────────────────────────────────────"
}

run_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

detect_apt_distro() {
  if [[ ! -f /etc/os-release ]]; then
    return 1
  fi
  # shellcheck source=/dev/null
  source /etc/os-release
  case "${ID:-}" in
    debian|ubuntu) return 0 ;;
    *) return 1 ;;
  esac
}

install_docker_debian() {
  print_separator
  echo "Installing Docker Engine + Compose plugin (apt) …"
  export DEBIAN_FRONTEND=noninteractive
  run_sudo apt-get update -y
  run_sudo apt-get install -y docker.io docker-compose-plugin ca-certificates curl
  if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
    run_sudo systemctl enable --now docker || true
  else
    echo "(No systemd here — ensure Docker daemon is reachable, e.g. via docker.sock on the host.)"
  fi
}

ensure_user_in_docker_group() {
  local unix_user="$1"
  if [[ -z "${unix_user}" ]] || ! id "${unix_user}" >/dev/null 2>&1; then
    return
  fi
  run_sudo usermod -aG docker "${unix_user}"
  echo "User '${unix_user}' added to group 'docker' (re-login or newgrp docker before rootless compose)."
}

apply_env_key_value() {
  local file_path="$1"
  local key="$2"
  local value="$3"
  if [[ ! -f "${file_path}" ]]; then
    echo "Missing ${file_path}" >&2
    return 1
  fi
  if command -v python3 >/dev/null 2>&1; then
    DEPLOY_ENV_FILE="${file_path}" DEPLOY_ENV_KEY="${key}" DEPLOY_ENV_VALUE="${value}" python3 <<'PY'
import os

path = os.environ["DEPLOY_ENV_FILE"]
key = os.environ["DEPLOY_ENV_KEY"]
val = os.environ["DEPLOY_ENV_VALUE"]
with open(path, encoding="utf-8") as handle:
    lines = handle.read().splitlines()
out = []
seen = False
for line in lines:
    if line.startswith(key + "="):
        out.append(key + "=" + val)
        seen = True
    else:
        out.append(line)
if not seen:
    out.append(key + "=" + val)
with open(path, "w", encoding="utf-8") as handle:
    handle.write("\n".join(out) + "\n")
PY
    return
  fi
  echo "python3 not found — set ${key} manually in ${file_path}" >&2
}

resolve_deploy_directory() {
  print_separator
  echo "This wizard configures the directory where GitHub Actions will run: git fetch/checkout tag + docker compose."
  echo "Current repository root (from your clone): ${repository_root}"
  read -r -p "Use THIS clone as the deploy directory? [Y/n]: " use_this
  use_this="${use_this:-Y}"
  if [[ "${use_this}" =~ ^[yY] ]]; then
    deploy_directory="$(cd "${repository_root}" && pwd)"
    echo "Deploy directory: ${deploy_directory}"
    return
  fi

  read -r -p "Git clone URL (must work from this server): " clone_url
  if [[ -z "${clone_url}" ]]; then
    echo "Clone URL is required." >&2
    exit 1
  fi
  read -r -p "Absolute deploy directory path (will clone here): " deploy_directory
  if [[ -z "${deploy_directory}" ]]; then
    echo "Path is required." >&2
    exit 1
  fi
  deploy_directory="${deploy_directory%/}"
  read -r -p "Git branch to track [main]: " git_branch
  git_branch="${git_branch:-main}"
  read -r -p "Shallow clone (--depth 1)? Not recommended for release tags — type Y only if you know why [y/N]: " shallow_answer
  shallow_clone=false
  if [[ "${shallow_answer:-}" =~ ^[yY] ]]; then
    shallow_clone=true
  fi

  parent_directory="$(dirname "${deploy_directory}")"
  mkdir -p "${parent_directory}"
  if [[ -d "${deploy_directory}/.git" ]]; then
    echo "Already a repo at ${deploy_directory}; pulling ${git_branch} …"
    git -C "${deploy_directory}" fetch origin
    git -C "${deploy_directory}" checkout "${git_branch}"
    git -C "${deploy_directory}" pull --ff-only origin "${git_branch}"
  elif [[ -e "${deploy_directory}" ]]; then
    echo "Path exists but is not a git repo: ${deploy_directory}" >&2
    exit 1
  else
    if [[ "${shallow_clone}" == true ]]; then
      git clone --depth 1 --branch "${git_branch}" "${clone_url}" "${deploy_directory}"
    else
      git clone --branch "${git_branch}" "${clone_url}" "${deploy_directory}"
    fi
  fi
  deploy_directory="$(cd "${deploy_directory}" && pwd)"
  echo "Deploy directory: ${deploy_directory}"
}

ensure_docker_available() {
  if docker compose version >/dev/null 2>&1; then
    echo "Docker Compose is already available."
    return
  fi
  echo "Docker Compose not found."
  if detect_apt_distro; then
    read -r -p "Install Docker via apt now? [Y/n]: " install_answer
    install_answer="${install_answer:-Y}"
    if [[ "${install_answer}" =~ ^[yY] ]]; then
      install_docker_debian
    else
      echo "Install Docker manually, then re-run this wizard." >&2
      exit 1
    fi
  else
    echo "Automatic Docker install is only implemented for Debian/Ubuntu. Install Docker + Compose plugin, then re-run." >&2
    exit 1
  fi
}

configure_git_safe_directory() {
  local directory_path="$1"
  git config --global --add safe.directory "${directory_path}" 2>/dev/null || true
}

offer_unshallow() {
  local directory_path="$1"
  if [[ "$(git -C "${directory_path}" rev-parse --is-shallow-repository 2>/dev/null)" != "true" ]]; then
    return
  fi
  print_separator
  echo "This clone is shallow. Release deploys need tags; fetching full history is safer."
  read -r -p "Run: git fetch --unshallow ? [Y/n]: " unshallow_answer
  unshallow_answer="${unshallow_answer:-Y}"
  if [[ "${unshallow_answer}" =~ ^[yY] ]]; then
    git -C "${directory_path}" fetch --unshallow || git -C "${directory_path}" fetch --depth=2147483647
  fi
}

configure_environment_file() {
  local directory_path="$1"
  local environment_example="${directory_path}/.env.example"
  local environment_target="${directory_path}/.env"
  if [[ ! -f "${environment_example}" ]]; then
    echo "Missing .env.example in ${directory_path}" >&2
    exit 1
  fi
  if [[ ! -f "${environment_target}" ]]; then
    cp "${environment_example}" "${environment_target}"
    echo "Created ${environment_target}"
  else
    read -r -p ".env exists — reconfigure keys below without overwriting whole file? [Y/n]: " reconfigure
    reconfigure="${reconfigure:-Y}"
    if [[ ! "${reconfigure}" =~ ^[yY] ]]; then
      echo "Leaving .env unchanged."
      return
    fi
  fi

  print_separator
  echo "WireGuard / Compose settings (.env)"
  read -r -p "WIREGUARD_SERVER_PUBLIC_HOST (VPS public DNS or IP): " public_host
  read -r -p "WIREGUARD_SERVER_PORT [51820]: " server_port
  server_port="${server_port:-51820}"
  read -r -p "WIREGUARD_INTERNAL_SUBNET (e.g. 10.13.13.0) [10.13.13.0]: " internal_subnet
  internal_subnet="${internal_subnet:-10.13.13.0}"
  read -r -p "COMPOSE_PROJECT_NAME [vpn-production]: " compose_project_name
  compose_project_name="${compose_project_name:-vpn-production}"

  if [[ -n "${public_host}" ]]; then
    apply_env_key_value "${environment_target}" "WIREGUARD_SERVER_PUBLIC_HOST" "${public_host}"
  fi
  apply_env_key_value "${environment_target}" "WIREGUARD_SERVER_PORT" "${server_port}"
  apply_env_key_value "${environment_target}" "WIREGUARD_INTERNAL_SUBNET" "${internal_subnet}"
  apply_env_key_value "${environment_target}" "COMPOSE_PROJECT_NAME" "${compose_project_name}"
}

maybe_open_ufw() {
  local directory_path="$1"
  if ! command -v ufw >/dev/null 2>&1; then
    return
  fi
  local port_line
  port_line="$(grep -E '^WIREGUARD_SERVER_PORT=' "${directory_path}/.env" | tail -n1 || true)"
  local port_value="${port_line#WIREGUARD_SERVER_PORT=}"
  port_value="${port_value//\"/}"
  port_value="${port_value//\'/}"
  port_value="${port_value:-51820}"
  read -r -p "Open UDP ${port_value} in ufw? [y/N]: " ufw_answer
  if [[ "${ufw_answer:-}" =~ ^[yY] ]]; then
    run_sudo ufw allow "${port_value}/udp"
    echo "If ufw was inactive: sudo ufw enable (when you are ready)."
  fi
}

compose_up_now() {
  local directory_path="$1"
  print_separator
  read -r -p "Run 'docker compose up -d' now? [y/N]: " up_answer
  if [[ ! "${up_answer:-}" =~ ^[yY] ]]; then
    return
  fi
  (
    cd "${directory_path}"
    if [[ "$(id -u)" -eq 0 ]]; then
      docker compose up -d
    elif docker compose version >/dev/null 2>&1 && docker compose ps >/dev/null 2>&1; then
      docker compose up -d
    else
      echo "Trying sudo docker compose (your user may lack docker socket access) …"
      run_sudo docker compose up -d
    fi
  )
}

main() {
  echo ""
  echo "=== dockerfile-vpn — server setup wizard ==="
  echo ""

  local deploy_directory=""
  resolve_deploy_directory
  deploy_directory="$(cd "${deploy_directory}" && pwd)"

  if [[ ! -f "${deploy_directory}/docker-compose.yml" ]]; then
    echo "No docker-compose.yml in ${deploy_directory}" >&2
    exit 1
  fi

  ensure_docker_available

  local unix_login="${SUDO_USER:-${USER:-}}"
  if [[ -n "${unix_login}" ]] && [[ "$(id -u)" -ne 0 ]]; then
    read -r -p "Add '${unix_login}' to group docker (recommended)? [Y/n]: " group_answer
    group_answer="${group_answer:-Y}"
    if [[ "${group_answer}" =~ ^[yY] ]]; then
      ensure_user_in_docker_group "${unix_login}"
    fi
  fi

  configure_git_safe_directory "${deploy_directory}"
  offer_unshallow "${deploy_directory}"

  configure_environment_file "${deploy_directory}"
  maybe_open_ufw "${deploy_directory}"

  compose_up_now "${deploy_directory}"

  print_separator
  cat <<EOF
=== Done ===

Set GitHub Actions Environment variable DEPLOY_DIRECTORY exactly to:

  ${deploy_directory}

Secrets per environment: SSH_HOST, SSH_USER, SSH_PRIVATE_KEY (deploy user must own this clone and run docker).

Publish a Release on GitHub → workflow checks out the release tag here and runs docker compose up.

Manual stack commands:
  cd ${deploy_directory}
  docker compose ps
  docker compose logs -f wireguard
EOF
}

main "$@"
