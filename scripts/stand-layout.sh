#!/usr/bin/env bash
## Compute isolated Compose project name, UDP port, and tunnel subnet for a stand on one VPS.
## Sourced by deploy scripts and documentation; may be run directly:
##   ./scripts/stand-layout.sh dev
##   ./scripts/stand-layout.sh test
##   ./scripts/stand-layout.sh mr 42
##
## Optional environment:
##   STAND_DNS_ZONE — e.g. vpn.example.com → hostnames dev.vpn.example.com, mr-42.vpn.example.com
##                    production uses the zone apex (vpn.example.com).

set -euo pipefail

stand_type="${1:-}"
stand_identifier="${2:-}"

if [[ -z "${stand_type}" ]]; then
  echo "usage: $0 <dev|test|uat|production|observability|mr> [pull_request_number]" >&2
  exit 1
fi

case "${stand_type}" in
  production|prod)
    compose_project_name="vpn-production"
    wireguard_server_port="51820"
    wireguard_internal_subnet="10.13.13.0"
    stand_directory_suffix="production"
    ;;
  uat)
    compose_project_name="vpn-uat"
    wireguard_server_port="51821"
    wireguard_internal_subnet="10.13.14.0"
    stand_directory_suffix="uat"
    ;;
  test)
    compose_project_name="vpn-test"
    wireguard_server_port="51822"
    wireguard_internal_subnet="10.13.22.0"
    stand_directory_suffix="test"
    ;;
  dev|development)
    compose_project_name="vpn-dev"
    wireguard_server_port="51823"
    wireguard_internal_subnet="10.13.23.0"
    stand_directory_suffix="dev"
    ;;
  observability)
    compose_project_name="vpn-observability"
    wireguard_server_port="0"
    wireguard_internal_subnet="0.0.0.0"
    stand_directory_suffix="observability"
    ;;
  mr|merge-request|merge_request)
    if [[ -z "${stand_identifier}" ]] || ! [[ "${stand_identifier}" =~ ^[0-9]+$ ]]; then
      echo "usage: $0 mr <pull_request_number>" >&2
      exit 1
    fi
    compose_project_name="vpn-mr-${stand_identifier}"
    # 51900–52999 reserved for MR previews (max ~1000 concurrent PR numbers in range)
    wireguard_server_port=$((51900 + stand_identifier))
    if (( wireguard_server_port > 52999 )); then
      echo "pull request number too large for port formula (51900 + N <= 52999): ${stand_identifier}" >&2
      exit 1
    fi
    # Unique /24 per PR: 10.20.<pr>.0 (PR must be 1–254 for third octet; larger PRs use modulo)
    subnet_third_octet=$((stand_identifier % 254 + 1))
    wireguard_internal_subnet="10.20.${subnet_third_octet}.0"
    stand_directory_suffix="mr-${stand_identifier}"
    ;;
  *)
    echo "unknown stand type: ${stand_type}" >&2
    exit 1
    ;;
esac

# shellcheck disable=SC2034
stand_directory_name="${stand_directory_suffix}"

wireguard_server_public_host=""
if [[ -n "${STAND_DNS_ZONE:-}" ]]; then
  stand_dns_zone="${STAND_DNS_ZONE%.}"
  case "${stand_type}" in
    production|prod)
      wireguard_server_public_host="${stand_dns_zone}"
      ;;
    uat)
      wireguard_server_public_host="uat.${stand_dns_zone}"
      ;;
    test)
      wireguard_server_public_host="test.${stand_dns_zone}"
      ;;
    dev|development)
      wireguard_server_public_host="dev.${stand_dns_zone}"
      ;;
    observability)
      wireguard_server_public_host="grafana.${stand_dns_zone}"
      ;;
    mr|merge-request|merge_request)
      wireguard_server_public_host="mr-${stand_identifier}.${stand_dns_zone}"
      ;;
  esac
fi

printf 'COMPOSE_PROJECT_NAME=%s\n' "${compose_project_name}"
printf 'WIREGUARD_SERVER_PORT=%s\n' "${wireguard_server_port}"
printf 'WIREGUARD_INTERNAL_SUBNET=%s\n' "${wireguard_internal_subnet}"
printf 'STAND_DIRECTORY_SUFFIX=%s\n' "${stand_directory_suffix}"
if [[ -n "${wireguard_server_public_host}" ]]; then
  printf 'WIREGUARD_SERVER_PUBLIC_HOST=%s\n' "${wireguard_server_public_host}"
fi
