#!/usr/bin/env bash
## Teardown VPS stands using the same per-environment SSH keys as launchpad.
##
##   TEARDOWN_CONFIRM=yes ./scripts/teardown-platform-run.sh

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

if [[ ! -f "${repository_root}/.env.platform" ]]; then
  echo "Missing .env.platform — copy from .env.platform.example" >&2
  exit 1
fi

# shellcheck source=/dev/null
set -a
source "${repository_root}/.env.platform"
set +a

# shellcheck source=lib/platform-environments.sh
source "${repository_root}/scripts/lib/platform-environments.sh"

if ! platform_environment_validate_all; then
  exit 1
fi

exec "${repository_root}/scripts/teardown-platform.sh"
