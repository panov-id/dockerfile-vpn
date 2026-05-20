#!/usr/bin/env bash
## Run diagnose-git-branches.sh inside the launchpad container (same mounts as launchpad-run).
##
##   ./scripts/launchpad-diagnose-git.sh
##   ./scripts/launchpad-diagnose-git.sh --try-create

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

compose_file="${repository_root}/docker/docker-compose.launchpad.yml"

# shellcheck source=lib/launchpad-preflight.sh
source "${repository_root}/scripts/lib/launchpad-preflight.sh"
launchpad_preflight_host "${repository_root}"

extra_args=()
if [[ "${1:-}" == "--try-create" ]]; then
  extra_args=(--try-create)
fi

export LAUNCHPAD_KEYS_DIRECTORY
docker compose -f "${compose_file}" build launchpad --quiet 2>/dev/null || \
  docker compose -f "${compose_file}" build launchpad

docker compose -f "${compose_file}" run --rm \
  --entrypoint /workspace/repo/scripts/diagnose-git-branches.sh \
  launchpad "${extra_args[@]}"
