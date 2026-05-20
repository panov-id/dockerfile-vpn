#!/usr/bin/env bash
## Source from setup scripts. Loads ${REPOSITORY_ROOT}/.env.platform
## Per-environment fields only — no global SSH_HOST fallback.

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

  local platform_environments_script="${repository_root}/scripts/lib/platform-environments.sh"
  # shellcheck source=/dev/null
  source "${platform_environments_script}"

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

  SETUP_GITHUB="${SETUP_GITHUB:-true}"
  SETUP_GITHUB_STRICT="${SETUP_GITHUB_STRICT:-true}"
  SETUP_VPS="${SETUP_VPS:-true}"
  SETUP_VPS_INSTALL_DOCKER="${SETUP_VPS_INSTALL_DOCKER:-true}"
  SETUP_CREATE_BRANCHES="${SETUP_CREATE_BRANCHES:-true}"
  SETUP_LOCAL_COMPOSE_CHECK="${SETUP_LOCAL_COMPOSE_CHECK:-true}"

  if [[ -z "${GIT_REMOTE_URL:-}" ]]; then
    local git_ssh_host="${GH_HOST:-github.com}"
    GIT_REMOTE_URL="git@${git_ssh_host}:${GITHUB_REPOSITORY_SLUG}.git"
  fi

  if [[ -z "${GITHUB_TOKEN:-}" ]] && [[ "${LAUNCHPAD_CONTAINER:-}" != true ]] && ! command -v gh >/dev/null 2>&1; then
    echo "Install gh or set GITHUB_TOKEN in ${config_file}, or use ./scripts/launchpad-run.sh" >&2
    return 1
  fi

  if [[ "${LAUNCHPAD_CONTAINER:-}" == true && -z "${GITHUB_TOKEN:-}" ]]; then
    echo "Set GITHUB_TOKEN in ${config_file} for launchpad (no gh on host)." >&2
    return 1
  fi

  if ! platform_environment_validate_all; then
    return 1
  fi

  if ! platform_environment_validate_shared_server_layout; then
    return 1
  fi

  export GITHUB_REPOSITORY_SLUG GIT_REMOTE_URL GITHUB_TOKEN
  export SETUP_GITHUB SETUP_GITHUB_STRICT SETUP_VPS SETUP_VPS_INSTALL_DOCKER SETUP_CREATE_BRANCHES SETUP_LOCAL_COMPOSE_CHECK
  export LAUNCHPAD_CONTAINER LAUNCHPAD_KEYS_DIRECTORY GH_HOST GITHUB_API_URL PLATFORM_ENVIRONMENTS
  return 0
}
