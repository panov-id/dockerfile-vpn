#!/usr/bin/env bash
## Run ON the VPS. Stops and removes an MR preview stand directory.
##
## Environment:
##   STANDS_ROOT
##   PULL_REQUEST_NUMBER

set -euo pipefail

stands_root="${STANDS_ROOT:?STANDS_ROOT is required}"
pull_request_number="${PULL_REQUEST_NUMBER:?PULL_REQUEST_NUMBER is required}"

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
stands_tooling_directory="${STANDS_TOOLING_DIRECTORY:?STANDS_TOOLING_DIRECTORY is required}"
layout_script="${script_directory}/../stand-layout.sh"
if [[ ! -f "${layout_script}" ]]; then
  layout_script="${stands_tooling_directory}/stand-layout.sh"
fi
# shellcheck source=/dev/null
eval "$("${layout_script}" mr "${pull_request_number}")"

stands_root="${stands_root%/}"
deploy_directory="${stands_root}/${STAND_DIRECTORY_SUFFIX}"

if [[ ! -d "${deploy_directory}" ]]; then
  echo "Nothing to tear down: ${deploy_directory} does not exist"
  exit 0
fi

cd "${deploy_directory}"
if [[ -f docker-compose.yml ]] && [[ -f .env ]]; then
  docker compose down -v --remove-orphans 2>/dev/null || docker compose down --remove-orphans || true
fi

cd "${stands_root}"
rm -rf "${deploy_directory}"
echo "Removed MR stand: ${deploy_directory}"
