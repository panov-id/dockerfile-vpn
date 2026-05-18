#!/usr/bin/env bash
## Resolve WIREGUARD_SERVER_PUBLIC_HOST for a stand (stdout: single hostname).
## Uses STAND_DNS_ZONE when set; otherwise prints WIREGUARD_SERVER_PUBLIC_HOST from the environment.
##
##   STAND_DNS_ZONE=vpn.example.com ./scripts/stand-resolve-public-host.sh mr 42
##   WIREGUARD_SERVER_PUBLIC_HOST=legacy.example.com ./scripts/stand-resolve-public-host.sh dev

set -euo pipefail

stand_type="${1:-}"
stand_identifier="${2:-}"

if [[ -z "${stand_type}" ]]; then
  echo "usage: $0 <stand_type> [pull_request_number]" >&2
  exit 1
fi

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
layout_script="${script_directory}/stand-layout.sh"

if [[ -n "${STAND_DNS_ZONE:-}" ]]; then
  if [[ "${stand_type}" == mr ]]; then
    # shellcheck source=/dev/null
    eval "$("${layout_script}" mr "${stand_identifier}")"
  else
    # shellcheck source=/dev/null
    eval "$("${layout_script}" "${stand_type}")"
  fi
  if [[ -n "${WIREGUARD_SERVER_PUBLIC_HOST:-}" ]]; then
    printf '%s\n' "${WIREGUARD_SERVER_PUBLIC_HOST}"
    exit 0
  fi
fi

if [[ -n "${WIREGUARD_SERVER_PUBLIC_HOST:-}" ]]; then
  printf '%s\n' "${WIREGUARD_SERVER_PUBLIC_HOST}"
  exit 0
fi

echo "Set STAND_DNS_ZONE (e.g. vpn.example.com) or WIREGUARD_SERVER_PUBLIC_HOST" >&2
exit 1
