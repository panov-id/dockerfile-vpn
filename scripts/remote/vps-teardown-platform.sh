#!/usr/bin/env bash
## Run ON the VPS. Stops WireGuard stands and removes directories created by launchpad.
##
## Environment:
##   STANDS_ROOT
##   STANDS_TOOLING_DIRECTORY
##   TEARDOWN_STANDS — comma list: dev,test,uat,production (required)
##   TEARDOWN_REMOVE_MR_STANDS — true|false (default true)
##   TEARDOWN_REMOVE_TOOLING — true|false (default true)

set -euo pipefail

stands_root="${STANDS_ROOT:?STANDS_ROOT is required}"
stands_tooling_directory="${STANDS_TOOLING_DIRECTORY:?STANDS_TOOLING_DIRECTORY is required}"
teardown_stands="${TEARDOWN_STANDS:-}"
teardown_remove_mr_stands="${TEARDOWN_REMOVE_MR_STANDS:-true}"
teardown_remove_tooling="${TEARDOWN_REMOVE_TOOLING:-true}"

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
stands_tooling_directory="${stands_tooling_directory%/}"
stands_root="${stands_root%/}"

teardown_stand_directory() {
  local deploy_directory="$1"
  if [[ ! -d "${deploy_directory}" ]]; then
    echo "  skip (missing): ${deploy_directory}"
    return 0
  fi
  if [[ -f "${deploy_directory}/docker-compose.yml" ]] && [[ -f "${deploy_directory}/.env" ]]; then
    (
      cd "${deploy_directory}"
      docker compose down -v --remove-orphans 2>/dev/null || docker compose down --remove-orphans || true
    )
  fi
  rm -rf "${deploy_directory}"
  echo "  removed: ${deploy_directory}"
}

teardown_mr_preview_directories() {
  local entry_name deploy_directory
  shopt -s nullglob
  for entry_name in "${stands_root}"/mr-*; do
    [[ -d "${entry_name}" ]] || continue
    deploy_directory="${entry_name}"
    if [[ -f "${deploy_directory}/docker-compose.yml" ]]; then
      (
        cd "${deploy_directory}"
        docker compose down -v --remove-orphans 2>/dev/null || docker compose down --remove-orphans || true
      )
    fi
    rm -rf "${deploy_directory}"
    echo "  removed MR stand: ${deploy_directory}"
  done
  shopt -u nullglob
}

echo "=== vps-teardown-platform ==="
echo "STANDS_ROOT=${stands_root}"

if [[ -z "${teardown_stands// }" && "${teardown_remove_mr_stands}" != true ]]; then
  echo "Nothing to tear down (set TEARDOWN_STANDS and/or TEARDOWN_REMOVE_MR_STANDS=true)." >&2
  exit 1
fi

local_stand_type
local_stand_list="${teardown_stands//,/ }"
for local_stand_type in ${local_stand_list}; do
  local_stand_type="$(echo "${local_stand_type}" | tr -d ' ')"
  [[ -z "${local_stand_type}" ]] && continue
  case "${local_stand_type}" in
    dev|test|uat|production)
      teardown_stand_directory "${stands_root}/${local_stand_type}"
      ;;
    *)
      echo "Unknown stand in TEARDOWN_STANDS: ${local_stand_type}" >&2
      exit 1
      ;;
  esac
done

if [[ "${teardown_remove_mr_stands}" == true ]]; then
  teardown_mr_preview_directories
fi

if [[ "${teardown_remove_tooling}" == true && -d "${stands_tooling_directory}" ]]; then
  rm -rf "${stands_tooling_directory}"
  echo "  removed tooling: ${stands_tooling_directory}"
fi

echo "=== vps-teardown-platform finished ==="
