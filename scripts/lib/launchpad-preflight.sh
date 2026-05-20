#!/usr/bin/env bash
## Shared host checks before launchpad / diagnose containers run.

launchpad_preflight_host() {
  local repository_root="${1:?repository root required}"

  if [[ ! -f "${repository_root}/.env.platform" ]]; then
    echo "Missing ${repository_root}/.env.platform — cp .env.platform.example .env.platform" >&2
    return 1
  fi

  # shellcheck source=/dev/null
  set -a
  source "${repository_root}/.env.platform"
  set +a

  # shellcheck source=platform-environments.sh
  source "${repository_root}/scripts/lib/platform-environments.sh"

  if [[ -n "${SSH_HOST:-}" ]]; then
    echo "Warning: legacy SSH_HOST in .env.platform is ignored — use PRODUCTION_SSH_HOST, DEV_SSH_HOST, …" >&2
    echo "  Run ./scripts/migrate-env-platform-per-environment.sh or remove SSH_HOST manually." >&2
  fi

  if ! platform_environment_validate_names; then
    return 1
  fi

  if ! platform_environment_validate_all; then
    return 1
  fi

  if ! platform_environment_validate_shared_server_layout; then
    return 1
  fi

  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "Set GITHUB_TOKEN in .env.platform." >&2
    return 1
  fi

  # shellcheck source=launchpad-stage-ssh-keys.sh
  source "${repository_root}/scripts/lib/launchpad-stage-ssh-keys.sh"
  stage_launchpad_ssh_keys "${repository_root}"

  export LAUNCHPAD_KEYS_DIRECTORY
  return 0
}
