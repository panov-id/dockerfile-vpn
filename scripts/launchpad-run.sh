#!/usr/bin/env bash
## Run setup-platform.sh inside the launchpad container (gh, git, ssh — not on host).
##
## Host needs only: Docker + .env.platform (+ SSH key file path).
##
##   cp .env.platform.example .env.platform
##   # Fill GITHUB_TOKEN, SSH_*, STAND_DNS_ZONE, LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH
##   ./scripts/launchpad-run.sh

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

compose_file="${repository_root}/docker/docker-compose.launchpad.yml"

if [[ ! -f "${repository_root}/.env.platform" ]]; then
  if [[ -f "${repository_root}/.env.platform.example" ]]; then
    cp "${repository_root}/.env.platform.example" "${repository_root}/.env.platform"
  fi
  echo "Created .env.platform — fill REQUIRED fields (especially GITHUB_TOKEN and LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH), then re-run." >&2
  exit 1
fi

# Load only SSH path on host — do not export GITHUB_TOKEN into docker compose (breaks gh in entrypoint).
# shellcheck source=/dev/null
source "${repository_root}/.env.platform"

launchpad_ssh_key_host_path="${LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH:-${SSH_PRIVATE_KEY_FILE:-}}"
if [[ -z "${launchpad_ssh_key_host_path}" ]]; then
  echo "Set LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH in .env.platform (absolute path to deploy private key on this machine)." >&2
  exit 1
fi
if [[ ! -f "${launchpad_ssh_key_host_path}" ]]; then
  echo "SSH private key not found: ${launchpad_ssh_key_host_path}" >&2
  exit 1
fi

export LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH="${launchpad_ssh_key_host_path}"

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose is required on the host to run the launchpad container." >&2
  exit 1
fi

echo "=== launchpad: verify deploy SSH key (no passphrase) ==="
"${repository_root}/scripts/verify-deploy-ssh-key.sh"

echo "=== launchpad: building image (gh + git + ssh inside container) ==="
docker compose -f "${compose_file}" build launchpad

echo "=== launchpad: running setup-platform.sh ==="
docker compose -f "${compose_file}" run --rm launchpad
