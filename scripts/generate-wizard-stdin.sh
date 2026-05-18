#!/usr/bin/env bash
## Print wizard answers from .env.platform (for server-setup-wizard.sh on VPS).
## Usage on server after copying .env.platform:
##   ./scripts/generate-wizard-stdin.sh | ./scripts/server-setup-wizard.sh
##
## Or from laptop over SSH:
##   ssh user@vps 'bash -s' < scripts/generate-wizard-stdin.sh | ...

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/load-platform-config.sh
source "${repository_root}/scripts/lib/load-platform-config.sh"
load_platform_config "${repository_root}" || exit 1

stand_type="${WIZARD_STAND_TYPE:-production}"
skip_compose_up="${WIZARD_SKIP_COMPOSE_UP:-true}"

layout_script="${repository_root}/scripts/stand-layout.sh"
# shellcheck source=/dev/null
eval "$("${layout_script}" "${stand_type}")"

answers=( '' ) # use this clone

if [[ "$(git -C "${repository_root}" rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then
  answers+=( 'Y' )
fi

answers+=( "${stand_type}" )

if [[ -f "${repository_root}/.env" ]]; then
  answers+=( 'Y' )
fi

public_host="$(STAND_DNS_ZONE="${STAND_DNS_ZONE}" "${repository_root}/scripts/stand-resolve-public-host.sh" "${stand_type}")"
answers+=(
  "${public_host}"
  "${WIREGUARD_SERVER_PORT}"
  "${WIREGUARD_INTERNAL_SUBNET}"
  "${COMPOSE_PROJECT_NAME}"
)

if command -v ufw >/dev/null 2>&1; then
  answers+=( 'y' )
fi

if [[ "${skip_compose_up}" == true ]] || [[ "${skip_compose_up}" == 1 ]]; then
  answers+=( 'n' )
else
  answers+=( 'y' )
fi

printf '%s\n' "${answers[@]}"
