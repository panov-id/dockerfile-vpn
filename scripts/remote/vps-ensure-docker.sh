#!/usr/bin/env bash
## Run on the VPS (SSH from launchpad or from vps-deploy-stand). Installs Docker if missing.
##
## Environment:
##   STANDS_TOOLING_DIRECTORY — e.g. /srv/vpn/_tooling (contains lib/vps-docker.sh)
##   VPS_DOCKER_DEPLOY_UNIX_USER — SSH user for docker group (optional; root skips group)

set -euo pipefail

stands_tooling_directory="${STANDS_TOOLING_DIRECTORY:-}"
if [[ -z "${stands_tooling_directory}" ]]; then
  stands_tooling_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

library_script="${stands_tooling_directory}/lib/vps-docker.sh"
if [[ ! -f "${library_script}" ]]; then
  echo "Missing ${library_script} (re-run launchpad to upload tooling)." >&2
  exit 1
fi

# shellcheck source=../lib/vps-docker.sh
source "${library_script}"

deploy_unix_user="${VPS_DOCKER_DEPLOY_UNIX_USER:-root}"
vps_ensure_docker_installed "${deploy_unix_user}"
