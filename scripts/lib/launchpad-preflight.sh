#!/usr/bin/env bash
## Shared host checks before launchpad / diagnose containers run.

launchpad_preflight_host() {
  local repository_root="${1:?repository root required}"

  if [[ ! -f "${repository_root}/.env.platform" ]]; then
    echo "Missing ${repository_root}/.env.platform — cp .env.platform.example .env.platform" >&2
    return 1
  fi

  local manifest_loader="${repository_root}/scripts/lib/read-platform-manifest.sh"
  if [[ -f "${manifest_loader}" ]]; then
    # shellcheck source=read-platform-manifest.sh
    source "${manifest_loader}"
    load_platform_manifest "${repository_root}"
    if [[ -n "${PLATFORM_ENVIRONMENTS_FROM_MANIFEST:-}" ]]; then
      export PLATFORM_ENVIRONMENTS="${PLATFORM_ENVIRONMENTS_FROM_MANIFEST}"
    fi
  fi

  # shellcheck source=/dev/null
  set -a
  source "${repository_root}/.env.platform"
  set +a

  # shellcheck source=platform-environments.sh
  source "${repository_root}/scripts/lib/platform-environments.sh"

  if ! platform_environment_reject_legacy_variables; then
    return 1
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
