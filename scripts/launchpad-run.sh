#!/usr/bin/env bash
## Run Platform Launchpad against this application (see .platform.yaml + .env.platform).
##
##   cp .platform.yaml.example .platform.yaml
##   cp .env.platform.example .env.platform
##   ./scripts/launchpad-run.sh

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

if [[ ! -f "${repository_root}/.env.platform" ]]; then
  if [[ -f "${repository_root}/.env.platform.example" ]]; then
    cp "${repository_root}/.env.platform.example" "${repository_root}/.env.platform"
  fi
  echo "Created .env.platform — fill per-environment blocks, then re-run." >&2
  exit 1
fi

if [[ ! -f "${repository_root}/.platform.yaml" ]]; then
  if [[ -f "${repository_root}/.platform.yaml.example" ]]; then
    cp "${repository_root}/.platform.yaml.example" "${repository_root}/.platform.yaml"
    echo "Created .platform.yaml — review platform_launchpad version, then re-run." >&2
    exit 1
  fi
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose is required on the host." >&2
  exit 1
fi

echo "=== verify deploy SSH keys (all environments) ==="
"${repository_root}/scripts/verify-deploy-ssh-key.sh"

# shellcheck source=lib/platform-launchpad-client.sh
source "${repository_root}/scripts/lib/platform-launchpad-client.sh"
run_platform_launchpad "${repository_root}"
