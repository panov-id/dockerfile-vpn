#!/usr/bin/env bash
## One-shot VPS preparation: install Git + Docker + Compose (Debian/Ubuntu),
## clone this repository into a deploy directory (unless already present), seed .env,
## optionally open WireGuard UDP in ufw.
##
## Prefer **`scripts/server-setup-wizard.sh`** if Git is already on the server and you want an interactive flow after `git clone`.
##
## Run as root: sudo ...
##
## Typical first run (empty directory — will clone):
##   sudo VPS_DEPLOY_GIT_URL='git@github.com:panov-id/dockerfile-vpn.git' \
##        VPS_DEPLOY_DIRECTORY='/opt/dockerfile-vpn/production' \
##        ./scripts/vps-bootstrap.sh
##
## If you already cloned the repo to that path yourself:
##   sudo VPS_DEPLOY_GIT_URL='git@github.com:panov-id/dockerfile-vpn.git' \
##        VPS_DEPLOY_DIRECTORY='/opt/dockerfile-vpn/production' \
##        ./scripts/vps-bootstrap.sh --skip-clone
##
## After the script: edit VPS_DEPLOY_DIRECTORY/.env (host, port, subnet), open UDP in the
## cloud firewall, then: cd VPS_DEPLOY_DIRECTORY && docker compose up -d

set -euo pipefail

skip_clone=false
if [[ "${1:-}" == "--skip-clone" ]]; then
  skip_clone=true
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

VPS_DEPLOY_GIT_URL="${VPS_DEPLOY_GIT_URL:-}"
VPS_DEPLOY_DIRECTORY="${VPS_DEPLOY_DIRECTORY:-/opt/dockerfile-vpn/production}"
VPS_GIT_BRANCH="${VPS_GIT_BRANCH:-main}"
VPS_UNIX_OWNER="${VPS_UNIX_OWNER:-}"
OPEN_UFW_WIREGUARD="${OPEN_UFW_WIREGUARD:-false}"

if [[ "${skip_clone}" != true && -z "${VPS_DEPLOY_GIT_URL}" ]]; then
  echo "Set VPS_DEPLOY_GIT_URL (git clone URL with read access from this server)." >&2
  exit 1
fi

if [[ "${skip_clone}" == true && ! -d "${VPS_DEPLOY_DIRECTORY}/.git" ]]; then
  echo "--skip-clone requires an existing git repo at VPS_DEPLOY_DIRECTORY (${VPS_DEPLOY_DIRECTORY})." >&2
  exit 1
fi

normalize_directory_path() {
  local path="$1"
  path="${path%/}"
  echo "${path}"
}

VPS_DEPLOY_DIRECTORY="$(normalize_directory_path "${VPS_DEPLOY_DIRECTORY}")"

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

install_packages_debian() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y git ca-certificates curl docker.io docker-compose-plugin
  systemctl enable --now docker
}

infer_unix_owner() {
  if [[ -n "${VPS_UNIX_OWNER}" ]]; then
    echo "${VPS_UNIX_OWNER}"
    return
  fi
  if [[ -n "${SUDO_USER:-}" ]]; then
    echo "${SUDO_USER}"
    return
  fi
  echo ""
}

resolve_wireguard_udp_port_for_firewall() {
  local environment_file="${VPS_DEPLOY_DIRECTORY}/.env"
  local port_line
  if [[ -f "${environment_file}" ]]; then
    port_line="$(grep -E '^WIREGUARD_SERVER_PORT=' "${environment_file}" | tail -n1 || true)"
  fi
  if [[ -z "${port_line}" ]]; then
    port_line="$(grep -E '^WIREGUARD_SERVER_PORT=' "${VPS_DEPLOY_DIRECTORY}/.env.example" | tail -n1 || true)"
  fi
  local value="${port_line#WIREGUARD_SERVER_PORT=}"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  if [[ -z "${value}" ]]; then
    echo "51820"
  else
    echo "${value}"
  fi
}

echo "=== dockerfile-vpn VPS bootstrap ==="
echo "Deploy directory: ${VPS_DEPLOY_DIRECTORY}"

if ! detect_apt_distro; then
  echo "This script only installs Docker automatically on Debian/Ubuntu." >&2
  echo "Install Docker Engine + Compose plugin + git manually, then re-run with --skip-clone after cloning." >&2
  exit 1
fi

echo "=== Installing git + Docker (apt) ==="
install_packages_debian

unix_owner="$(infer_unix_owner)"
if [[ -n "${unix_owner}" ]] && id "${unix_owner}" >/dev/null 2>&1; then
  echo "=== Adding ${unix_owner} to group docker ==="
  usermod -aG docker "${unix_owner}"
fi

if [[ "${skip_clone}" != true ]]; then
  parent_directory="$(dirname "${VPS_DEPLOY_DIRECTORY}")"
  mkdir -p "${parent_directory}"
  if [[ -e "${VPS_DEPLOY_DIRECTORY}" ]] && [[ ! -d "${VPS_DEPLOY_DIRECTORY}/.git" ]]; then
    echo "Path exists but is not a git repo: ${VPS_DEPLOY_DIRECTORY}" >&2
    exit 1
  fi
  if [[ ! -d "${VPS_DEPLOY_DIRECTORY}/.git" ]]; then
    echo "=== Cloning ${VPS_DEPLOY_GIT_URL} → ${VPS_DEPLOY_DIRECTORY} ==="
    git clone --branch "${VPS_GIT_BRANCH}" "${VPS_DEPLOY_GIT_URL}" "${VPS_DEPLOY_DIRECTORY}"
  else
    echo "=== Repository already present, fetching ==="
    git -C "${VPS_DEPLOY_DIRECTORY}" fetch origin
    git -C "${VPS_DEPLOY_DIRECTORY}" checkout "${VPS_GIT_BRANCH}"
    git -C "${VPS_DEPLOY_DIRECTORY}" pull --ff-only origin "${VPS_GIT_BRANCH}"
  fi
else
  echo "=== --skip-clone: updating existing repo ==="
  git -C "${VPS_DEPLOY_DIRECTORY}" fetch origin
  git -C "${VPS_DEPLOY_DIRECTORY}" checkout "${VPS_GIT_BRANCH}"
  git -C "${VPS_DEPLOY_DIRECTORY}" pull --ff-only origin "${VPS_GIT_BRANCH}"
fi

if [[ -n "${unix_owner}" ]] && id "${unix_owner}" >/dev/null 2>&1; then
  echo "=== Changing owner to ${unix_owner} ==="
  chown -R "${unix_owner}:${unix_owner}" "${VPS_DEPLOY_DIRECTORY}"
fi

echo "=== Git safe.directory (avoids dubious ownership warnings for automation users) ==="
git config --system --add safe.directory "${VPS_DEPLOY_DIRECTORY}" 2>/dev/null || \
  git config --global --add safe.directory "${VPS_DEPLOY_DIRECTORY}"

environment_example="${VPS_DEPLOY_DIRECTORY}/.env.example"
environment_target="${VPS_DEPLOY_DIRECTORY}/.env"
if [[ ! -f "${environment_example}" ]]; then
  echo "Missing .env.example in repo checkout." >&2
  exit 1
fi
if [[ ! -f "${environment_target}" ]]; then
  echo "=== Creating .env from .env.example (edit before production use) ==="
  cp "${environment_example}" "${environment_target}"
  if [[ -n "${unix_owner}" ]] && id "${unix_owner}" >/dev/null 2>&1; then
    chown "${unix_owner}:${unix_owner}" "${environment_target}"
  fi
else
  echo "=== .env already exists — not overwriting ==="
fi

wireguard_udp_port="$(resolve_wireguard_udp_port_for_firewall)"
echo "=== Detected WireGuard UDP port for firewall hints: ${wireguard_udp_port} ==="

if [[ "${OPEN_UFW_WIREGUARD}" == "true" ]] && command -v ufw >/dev/null 2>&1; then
  echo "=== Opening UDP ${wireguard_udp_port} in ufw ==="
  ufw allow "${wireguard_udp_port}/udp"
  echo "If ufw was inactive, enable it deliberately when ready: ufw enable"
else
  echo "Cloud/host firewall: allow inbound UDP ${wireguard_udp_port} (and enable ufw rule manually if you use ufw)."
fi

cat <<EOF

=== Next steps (manual) ===
1. Edit: ${environment_target}
   - WIREGUARD_SERVER_PUBLIC_HOST (public DNS or IP of this VPS)
   - WIREGUARD_SERVER_PORT / WIREGUARD_INTERNAL_SUBNET / COMPOSE_PROJECT_NAME
2. Open the same UDP port in your provider's security group / firewall.
3. First bring-up (as a user in group docker, or via sudo):
     cd ${VPS_DEPLOY_DIRECTORY}
     docker compose up -d
4. GitHub Actions deploy uses git only on the server: fetch tag + docker compose up (see deploy-release.yml).

EOF
