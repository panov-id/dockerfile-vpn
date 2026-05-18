#!/usr/bin/env bash
## Starts two isolated local stacks (.env.local + .env.local.stack-b), runs smoke checks,
## then tears both down unless you pass --keep-running.
##
## Prerequisites:
##   cp .env.local.example .env.local
##   cp .env.local.stack-b.example .env.local.stack-b
##
## Usage:
##   ./scripts/local-two-stacks-test.sh
##   ./scripts/local-two-stacks-test.sh --keep-running

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

primary_environment_file="${PRIMARY_LOCAL_ENVIRONMENT_FILE:-${repository_root}/.env.local}"
secondary_environment_file="${SECONDARY_LOCAL_ENVIRONMENT_FILE:-${repository_root}/.env.local.stack-b}"

keep_running=false
if [[ "${1:-}" == "--keep-running" ]]; then
  keep_running=true
fi

for environment_file in "${primary_environment_file}" "${secondary_environment_file}"; do
  if [[ ! -f "${environment_file}" ]]; then
    echo "Missing ${environment_file}. Copy from the matching .example file." >&2
    exit 1
  fi
done

bring_down_both_stacks() {
  LOCAL_ENVIRONMENT_FILE="${primary_environment_file}" "${repository_root}/scripts/local-compose-down.sh" || true
  LOCAL_ENVIRONMENT_FILE="${secondary_environment_file}" "${repository_root}/scripts/local-compose-down.sh" || true
}

if [[ "${keep_running}" != true ]]; then
  trap bring_down_both_stacks EXIT
fi

echo "=== Stack A (primary) ==="
LOCAL_ENVIRONMENT_FILE="${primary_environment_file}" "${repository_root}/scripts/local-compose-up.sh"

echo "=== Stack B (secondary) ==="
LOCAL_ENVIRONMENT_FILE="${secondary_environment_file}" "${repository_root}/scripts/local-compose-up.sh"

echo "=== Smoke Stack A ==="
LOCAL_ENVIRONMENT_FILE="${primary_environment_file}" LOCAL_SMOKE_CHECK_SKIP_UP=true "${repository_root}/scripts/local-smoke-check.sh"

echo "=== Smoke Stack B ==="
LOCAL_ENVIRONMENT_FILE="${secondary_environment_file}" LOCAL_SMOKE_CHECK_SKIP_UP=true "${repository_root}/scripts/local-smoke-check.sh"

echo "--- UDP port mapping summary ---"
docker compose -f docker-compose.yml -f docker-compose.local.yml --env-file "${primary_environment_file}" ps wireguard
docker compose -f docker-compose.yml -f docker-compose.local.yml --env-file "${secondary_environment_file}" ps wireguard

if [[ "${keep_running}" == true ]]; then
  echo "Stacks left running (--keep-running). Stop with:"
  echo "  LOCAL_ENVIRONMENT_FILE=${primary_environment_file} ./scripts/local-compose-down.sh"
  echo "  LOCAL_ENVIRONMENT_FILE=${secondary_environment_file} ./scripts/local-compose-down.sh"
else
  echo "Two-stack test passed; shutting down both stacks."
fi
