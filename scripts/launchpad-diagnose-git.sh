#!/usr/bin/env bash
## Run diagnose-git-branches.sh inside the launchpad container (same mounts as launchpad-run).
##
##   ./scripts/launchpad-diagnose-git.sh
##   ./scripts/launchpad-diagnose-git.sh --try-create

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

compose_file="${repository_root}/docker/docker-compose.launchpad.yml"

if [[ ! -f "${repository_root}/.env.platform" ]]; then
  echo "Missing .env.platform — cp .env.platform.example .env.platform and fill secrets." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${repository_root}/.env.platform"

launchpad_ssh_key_host_path="${LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH:-${SSH_PRIVATE_KEY_FILE:-}}"
if [[ -z "${launchpad_ssh_key_host_path}" || ! -f "${launchpad_ssh_key_host_path}" ]]; then
  echo "Set LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH in .env.platform" >&2
  exit 1
fi
export LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH="${launchpad_ssh_key_host_path}"

extra_args=()
if [[ "${1:-}" == "--try-create" ]]; then
  extra_args=(--try-create)
fi

docker compose -f "${compose_file}" build launchpad --quiet 2>/dev/null || \
  docker compose -f "${compose_file}" build launchpad

docker compose -f "${compose_file}" run --rm \
  --entrypoint /workspace/repo/scripts/diagnose-git-branches.sh \
  launchpad "${extra_args[@]}"
