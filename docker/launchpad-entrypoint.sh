#!/usr/bin/env bash
set -euo pipefail

cd /workspace/repo

if [[ ! -f .env.platform ]]; then
  echo "Missing /workspace/repo/.env.platform — copy .env.platform.example on the host and fill secrets." >&2
  exit 1
fi

# shellcheck source=/dev/null
set -a
source .env.platform
set +a

# shellcheck source=scripts/lib/platform-environments.sh
source /workspace/repo/scripts/lib/platform-environments.sh

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "Set GITHUB_TOKEN in .env.platform (PAT with repo + Actions secrets/variables)." >&2
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
    echo "Missing SSH key mount for environment ${local_environment_name} at /run/launchpad/keys/${local_environment_name}" >&2
    echo "Re-run ./scripts/launchpad-run.sh on the host." >&2
    exit 1
  fi
  chmod 600 "/run/launchpad/keys/${local_environment_name}" 2>/dev/null || true
done < <(platform_environment_list)

export LAUNCHPAD_CONTAINER=true
export SETUP_LOCAL_COMPOSE_CHECK="${SETUP_LOCAL_COMPOSE_CHECK:-false}"

git config --global --add safe.directory /workspace/repo 2>/dev/null || true

exec ./scripts/setup-platform.sh
