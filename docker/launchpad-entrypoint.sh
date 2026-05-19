#!/usr/bin/env bash
set -euo pipefail

cd /workspace/repo

if [[ ! -f .env.platform ]]; then
  echo "Missing /workspace/repo/.env.platform — copy .env.platform.example on the host and fill secrets." >&2
  exit 1
fi

if [[ ! -f /run/launchpad/ssh_private_key ]]; then
  echo "Missing SSH key mount at /run/launchpad/ssh_private_key" >&2
  echo "Set LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH in .env.platform to your key path on the host." >&2
  exit 1
fi

chmod 600 /run/launchpad/ssh_private_key 2>/dev/null || true

# shellcheck source=/dev/null
set -a
source .env.platform
set +a

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "Set GITHUB_TOKEN in .env.platform (PAT with repo + Actions secrets/variables)." >&2
  exit 1
fi

echo "${GITHUB_TOKEN}" | gh auth login --with-token
gh auth status

export LAUNCHPAD_CONTAINER=true
export SSH_PRIVATE_KEY_FILE=/run/launchpad/ssh_private_key
export SETUP_LOCAL_COMPOSE_CHECK="${SETUP_LOCAL_COMPOSE_CHECK:-false}"

exec ./scripts/setup-platform.sh
