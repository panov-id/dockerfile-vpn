#!/usr/bin/env bash
## Bring up the stack (unless LOCAL_SMOKE_CHECK_SKIP_UP=true), then verify container,
## `wg show`, and presence of wg0.conf under LOCAL_WIREGUARD_CONFIG_DIRECTORY.
##
## Usage:
##   ./scripts/local-smoke-check.sh
##   LOCAL_ENVIRONMENT_FILE=/path/.env.local.stack-b ./scripts/local-smoke-check.sh

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

environment_file="${LOCAL_ENVIRONMENT_FILE:-${repository_root}/.env.local}"

if [[ ! -f "${environment_file}" ]]; then
  echo "Missing ${environment_file}. Copy from .env.local.example (or .env.local.stack-b.example)." >&2
  exit 1
fi

compose_arguments=( -f docker-compose.yml -f docker-compose.local.yml --env-file "${environment_file}" )

read_config_directory_relative_path() {
  local raw_line
  raw_line="$(grep -E '^LOCAL_WIREGUARD_CONFIG_DIRECTORY=' "${environment_file}" | tail -n1 || true)"
  local value="${raw_line#LOCAL_WIREGUARD_CONFIG_DIRECTORY=}"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  if [[ -z "${value}" ]]; then
    echo "./config.local"
  else
    echo "${value}"
  fi
}

resolve_host_path_for_config_directory() {
  local relative_or_absolute="$1"
  if [[ "${relative_or_absolute}" == /* ]]; then
    echo "${relative_or_absolute}"
    return
  fi
  relative_or_absolute="${relative_or_absolute#./}"
  echo "${repository_root}/${relative_or_absolute}"
}

config_directory_relative_path="$(read_config_directory_relative_path)"
wireguard_config_host_path="$(resolve_host_path_for_config_directory "${config_directory_relative_path}")"

if [[ "${LOCAL_SMOKE_CHECK_SKIP_UP:-false}" != "true" ]]; then
  docker compose "${compose_arguments[@]}" up -d wireguard
fi

echo "--- compose ps (${environment_file}) ---"
docker compose "${compose_arguments[@]}" ps wireguard

wait_until_wireguard_reports_listening_port() {
  local deadline_seconds=$((SECONDS + 60))
  local wireguard_show_output=""
  while (( SECONDS < deadline_seconds )); do
    if wireguard_show_output="$(docker compose "${compose_arguments[@]}" exec -T wireguard wg show 2>/dev/null)"; then
      if grep -q 'listening port:' <<<"${wireguard_show_output}"; then
        echo "${wireguard_show_output}"
        return 0
      fi
    fi
    sleep 2
  done
  echo "smoke-check failed: wg show did not report a listening port within 60s" >&2
  docker compose "${compose_arguments[@]}" logs --tail=80 wireguard >&2 || true
  exit 1
}

echo "--- wg show (${environment_file}) ---"
wait_until_wireguard_reports_listening_port

wireguard_conf_file="${wireguard_config_host_path}/wg_confs/wg0.conf"
if [[ ! -f "${wireguard_conf_file}" ]]; then
  echo "smoke-check failed: missing ${wireguard_conf_file}" >&2
  exit 1
fi

echo "smoke-check ok: $(basename "${environment_file}") → ${config_directory_relative_path}"
