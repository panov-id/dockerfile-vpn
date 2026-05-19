#!/usr/bin/env bash
## Source from setup scripts. Loads ${REPOSITORY_ROOT}/.env.platform
## Sets defaults and validates REQUIRED fields.

load_platform_config() {
  local repository_root="${1:?repository root required}"
  local config_file="${repository_root}/.env.platform"

  if [[ ! -f "${config_file}" ]]; then
    local example_file="${repository_root}/.env.platform.example"
    if [[ -f "${example_file}" ]]; then
      cp "${example_file}" "${config_file}"
      echo "Created ${config_file} from example — fill REQUIRED fields, then re-run." >&2
    else
      echo "Missing ${config_file} (and no .env.platform.example)." >&2
    fi
    return 1
  fi

  # shellcheck source=/dev/null
  set -a
  source "${config_file}"
  set +a

  if [[ -z "${GITHUB_REPOSITORY_SLUG:-}" ]]; then
    if git -C "${repository_root}" remote get-url origin >/dev/null 2>&1; then
      local origin_url
      origin_url="$(git -C "${repository_root}" remote get-url origin)"
      origin_url="${origin_url%.git}"
      case "${origin_url}" in
        https://github.com/*) GITHUB_REPOSITORY_SLUG="${origin_url#https://github.com/}" ;;
        git@github.com:*) GITHUB_REPOSITORY_SLUG="${origin_url#git@github.com:}" ;;
        git@*:*/*) GITHUB_REPOSITORY_SLUG="${origin_url#*:}" ;;
        *) GITHUB_REPOSITORY_SLUG="panov-id/dockerfile-vpn" ;;
      esac
    else
      GITHUB_REPOSITORY_SLUG="panov-id/dockerfile-vpn"
    fi
  fi

  STANDS_ROOT="${STANDS_ROOT:-/srv/vpn}"
  STANDS_TOOLING_DIRECTORY="${STANDS_TOOLING_DIRECTORY:-${STANDS_ROOT}/_tooling}"
  VPS_STANDS_TO_BOOTSTRAP="${VPS_STANDS_TO_BOOTSTRAP:-dev,test,uat,production}"

  SETUP_GITHUB="${SETUP_GITHUB:-true}"
  SETUP_VPS="${SETUP_VPS:-true}"
  SETUP_CREATE_BRANCHES="${SETUP_CREATE_BRANCHES:-true}"
  SETUP_LOCAL_COMPOSE_CHECK="${SETUP_LOCAL_COMPOSE_CHECK:-true}"

  if [[ -z "${GIT_REMOTE_URL:-}" ]]; then
    GIT_REMOTE_URL="git@github.com:${GITHUB_REPOSITORY_SLUG}.git"
  fi

  if [[ -z "${SSH_HOST:-}" || -z "${SSH_USER:-}" ]]; then
    echo "Set SSH_HOST and SSH_USER in ${config_file}" >&2
    return 1
  fi

  if [[ -z "${STAND_DNS_ZONE:-}" ]]; then
    echo "Set STAND_DNS_ZONE in ${config_file} (e.g. vpn.example.com)" >&2
    return 1
  fi

  if [[ "${LAUNCHPAD_CONTAINER:-}" == true ]]; then
    SSH_PRIVATE_KEY_FILE="${SSH_PRIVATE_KEY_FILE:-/run/launchpad/ssh_private_key}"
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
      echo "Set GITHUB_TOKEN in ${config_file} for launchpad (no gh on host)." >&2
      return 1
    fi
  else
    if [[ -z "${SSH_PRIVATE_KEY_FILE:-}" ]]; then
      echo "Set SSH_PRIVATE_KEY_FILE in ${config_file}" >&2
      return 1
    fi
    SSH_PRIVATE_KEY_FILE="${SSH_PRIVATE_KEY_FILE/#\~/${HOME}}"
    if [[ ! -f "${SSH_PRIVATE_KEY_FILE}" ]]; then
      echo "SSH private key not found: ${SSH_PRIVATE_KEY_FILE}" >&2
      return 1
    fi
    if [[ -z "${GITHUB_TOKEN:-}" ]] && ! command -v gh >/dev/null 2>&1; then
      echo "Install gh (sudo apt install gh) or set GITHUB_TOKEN in ${config_file}, or use ./scripts/launchpad-run.sh" >&2
      return 1
    fi
  fi

  export GITHUB_REPOSITORY_SLUG STANDS_ROOT STANDS_TOOLING_DIRECTORY
  export GIT_REMOTE_URL SSH_HOST SSH_USER SSH_PRIVATE_KEY_FILE STAND_DNS_ZONE
  export VPS_STANDS_TO_BOOTSTRAP SETUP_GITHUB SETUP_VPS SETUP_CREATE_BRANCHES SETUP_LOCAL_COMPOSE_CHECK
  export GITHUB_TOKEN LAUNCHPAD_CONTAINER LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH
}
