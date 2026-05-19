#!/usr/bin/env bash
set -euo pipefail

cd /workspace/repo

# shellcheck source=scripts/lib/ssh-deploy-key.sh
source /workspace/repo/scripts/lib/ssh-deploy-key.sh

if [[ ! -f .env.platform ]]; then
  echo "Missing /workspace/repo/.env.platform — copy .env.platform.example on the host and fill secrets." >&2
  exit 1
fi

if [[ ! -f /run/launchpad/ssh_private_key ]]; then
  echo "Missing SSH key mount at /run/launchpad/ssh_private_key" >&2
  echo "Set LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH in .env.platform (see docs/deploy-ssh-key.md)." >&2
  exit 1
fi

prepare_launchpad_ssh_private_key_copy \
  /run/launchpad/ssh_private_key \
  /tmp/launchpad_ssh_private_key

# shellcheck source=/dev/null
set -a
source .env.platform
set +a

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

export LAUNCHPAD_CONTAINER=true
export SSH_PRIVATE_KEY_FILE=/tmp/launchpad_ssh_private_key
export SETUP_LOCAL_COMPOSE_CHECK="${SETUP_LOCAL_COMPOSE_CHECK:-false}"

git config --global --add safe.directory /workspace/repo 2>/dev/null || true

exec ./scripts/setup-platform.sh
