#!/usr/bin/env bash
set -euo pipefail

application_root="${APP_REPOSITORY_ROOT:-/workspace/app}"
platform_root="${PLATFORM_ROOT:-${application_root}}"

cd "${application_root}"

if [[ ! -f "${application_root}/.env.platform" && -f /workspace/.env.platform ]]; then
  ln -sf /workspace/.env.platform "${application_root}/.env.platform" 2>/dev/null || true
fi

if [[ ! -f "${application_root}/.env.platform" ]]; then
  echo "Missing .env.platform on application root (${application_root})." >&2
  exit 1
fi

# shellcheck source=/dev/null
set -a
source "${application_root}/.env.platform"
set +a

# shellcheck source=scripts/lib/platform-environments.sh
source "${platform_root}/scripts/lib/platform-environments.sh"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "Set GITHUB_TOKEN in .env.platform." >&2
  exit 1
fi

export GH_TOKEN="${GITHUB_TOKEN}"
if [[ -n "${GH_HOST:-}" ]]; then
  export GH_HOST
  [[ -n "${GITHUB_API_URL:-}" ]] && export GITHUB_API_URL
fi
if ! gh auth status; then
  echo "GITHUB_TOKEN in .env.platform is missing or invalid." >&2
  exit 1
fi

while IFS= read -r local_environment_name; do
  [[ -z "${local_environment_name}" ]] && continue
  if [[ ! -f "/run/launchpad/keys/${local_environment_name}" ]]; then
    echo "Missing SSH key for ${local_environment_name} at /run/launchpad/keys/${local_environment_name}" >&2
    exit 1
  fi
  chmod 600 "/run/launchpad/keys/${local_environment_name}" 2>/dev/null || true
done < <(platform_environment_list)

export LAUNCHPAD_CONTAINER=true
export APP_REPOSITORY_ROOT="${application_root}"
export SETUP_LOCAL_COMPOSE_CHECK="${SETUP_LOCAL_COMPOSE_CHECK:-false}"

if [[ -n "${PLATFORM_PRODUCT_VERSION:-}" ]]; then
  echo "Platform Launchpad product version: ${PLATFORM_PRODUCT_VERSION}"
fi

git config --global --add safe.directory "${application_root}" 2>/dev/null || true

exec "${application_root}/scripts/setup-platform.sh"
