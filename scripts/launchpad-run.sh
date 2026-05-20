#!/usr/bin/env bash
## Run setup-platform.sh inside the launchpad container (gh, git, ssh — not on host).
##
## Host needs only: Docker + .env.platform (per-environment SSH settings).
##
##   cp .env.platform.example .env.platform
##   ./scripts/launchpad-run.sh

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

compose_file="${repository_root}/docker/docker-compose.launchpad.yml"

if [[ ! -f "${repository_root}/.env.platform" ]]; then
  if [[ -f "${repository_root}/.env.platform.example" ]]; then
    cp "${repository_root}/.env.platform.example" "${repository_root}/.env.platform"
  fi
  echo "Created .env.platform — fill every PRODUCTION_*, DEV_*, … block, then re-run." >&2
  exit 1
fi

# shellcheck source=lib/launchpad-preflight.sh
source "${repository_root}/scripts/lib/launchpad-preflight.sh"
launchpad_preflight_host "${repository_root}"

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose is required on the host to run the launchpad container." >&2
  exit 1
fi

echo "=== launchpad: verify deploy SSH keys (all environments) ==="
"${repository_root}/scripts/verify-deploy-ssh-key.sh"

echo "=== launchpad: building image (gh + git + ssh inside container) ==="
export LAUNCHPAD_KEYS_DIRECTORY
docker compose -f "${compose_file}" build launchpad

echo "=== launchpad: running setup-platform.sh ==="
docker compose -f "${compose_file}" run --rm launchpad
