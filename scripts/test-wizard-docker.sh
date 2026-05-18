#!/usr/bin/env bash
## Pipe scripted answers into scripts/server-setup-wizard.sh for CI or local inspection.
## Intended to run inside docker/docker-compose.wizard-test.yml (Debian + docker.sock).
##
## Environment:
##   WIZARD_TEST_PUBLIC_HOST        — value for WIREGUARD_SERVER_PUBLIC_HOST (default TEST-NET-3 doc IP)
##   WIZARD_TEST_SKIP_COMPOSE_UP    — if true, answer "n" to compose up (faster smoke)
##
## Prompt order must match server-setup-wizard.sh for the branch:
##   use-this-clone → optional unshallow → env fields → optional ufw → compose up

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose is required on PATH (see docker/docker-compose.wizard-test.yml)." >&2
  exit 1
fi

readonly answer_public_host="${WIZARD_TEST_PUBLIC_HOST:-203.0.113.50}"
readonly skip_compose_up="${WIZARD_TEST_SKIP_COMPOSE_UP:-false}"

answers=()

# Use THIS clone as deploy directory (default Y).
answers+=( '' )

# If checkout is shallow, wizard asks about git fetch --unshallow.
if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then
  answers+=( 'n' )
fi

answers+=(
  "${answer_public_host}"
  '' # WIREGUARD_SERVER_PORT → default 51820
  '' # WIREGUARD_INTERNAL_SUBNET → default
  '' # COMPOSE_PROJECT_NAME → default
)

if [[ "${skip_compose_up}" == "true" ]] || [[ "${skip_compose_up}" == "1" ]]; then
  answers+=( 'n' )
else
  answers+=( 'y' )
fi

echo "=== test-wizard-docker: piping ${#answers[@]} answer line(s) into server-setup-wizard.sh ==="
echo "=== WIZARD_TEST_PUBLIC_HOST=${answer_public_host} WIZARD_TEST_SKIP_COMPOSE_UP=${skip_compose_up} ==="
printf '%s\n' "${answers[@]}" | ./scripts/server-setup-wizard.sh
echo "=== test-wizard-docker: finished OK ==="
