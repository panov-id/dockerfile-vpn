#!/usr/bin/env bash
## Remove VPS resources created by launchpad (stands, MR dirs, tooling).
## Does NOT change GitHub environments or secrets.
##
##   TEARDOWN_CONFIRM=yes ./scripts/teardown-platform.sh
##   ./scripts/teardown-platform-run.sh
##
## Optional in .env.platform:
##   TEARDOWN_ENVIRONMENTS=production,uat,dev   # default: PLATFORM_ENVIRONMENTS
##   TEARDOWN_REMOVE_TOOLING=true               # default true

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

# shellcheck source=lib/load-platform-config.sh
source "${repository_root}/scripts/lib/load-platform-config.sh"

remote_teardown_platform_script="${repository_root}/scripts/remote/vps-teardown-platform.sh"

ssh_common_options=()
scp_common_options=()
ssh_target=""

log_step() {
  printf '\n=== %s ===\n' "$1"
}

platform_ssh_use_environment() {
  local environment_name="$1"
  local ssh_host ssh_user ssh_key_file
  ssh_host="$(platform_environment_require "${environment_name}" "SSH_HOST")"
  ssh_user="$(platform_environment_require "${environment_name}" "SSH_USER")"
  ssh_key_file="$(platform_environment_ssh_private_key_file "${environment_name}")"
  ssh_common_options=(-o StrictHostKeyChecking=accept-new -o BatchMode=yes -i "${ssh_key_file}")
  scp_common_options=(-o StrictHostKeyChecking=accept-new -i "${ssh_key_file}")
  ssh_target="${ssh_user}@${ssh_host}"
}

teardown_environment_list() {
  local configured="${TEARDOWN_ENVIRONMENTS:-}"
  if [[ -z "${configured}" ]]; then
    platform_environment_list
    return 0
  fi
  local item
  local normalized="${configured//,/ }"
  for item in ${normalized}; do
    item="$(echo "${item}" | tr -d ' ')"
    [[ -n "${item}" ]] && printf '%s\n' "${item}"
  done
}

collect_teardown_stands_for_server() {
  local server_id="$1"
  local environment_name server_for_environment
  local -a stand_accumulator=()
  local bootstrap_stands stand_type

  while IFS= read -r environment_name; do
    [[ -z "${environment_name}" ]] && continue
    server_for_environment="$(platform_environment_server_identity "${environment_name}")"
    [[ "${server_for_environment}" != "${server_id}" ]] && continue
    bootstrap_stands="$(platform_environment_bootstrap_stands "${environment_name}")"
    bootstrap_stands="${bootstrap_stands//,/ }"
    for stand_type in ${bootstrap_stands}; do
      stand_type="$(echo "${stand_type}" | tr -d ' ')"
      [[ -z "${stand_type}" ]] && continue
      stand_accumulator+=("${stand_type}")
    done
  done < <(teardown_environment_list)

  if [[ ${#stand_accumulator[@]} -eq 0 ]]; then
    printf '%s' ""
    return 0
  fi
  printf '%s' "$(printf '%s\n' "${stand_accumulator[@]}" | sort -u | paste -sd, -)"
}

server_teardown_includes_mr_stands() {
  local server_id="$1"
  local environment_name server_for_environment
  while IFS= read -r environment_name; do
    [[ -z "${environment_name}" ]] && continue
    [[ "${environment_name}" != mr-preview ]] && continue
    server_for_environment="$(platform_environment_server_identity "${environment_name}")"
    if [[ "${server_for_environment}" == "${server_id}" ]]; then
      return 0
    fi
  done < <(teardown_environment_list)
  return 1
}

upload_teardown_script_to_server() {
  local stands_tooling_directory="$1"
  ssh "${ssh_common_options[@]}" "${ssh_target}" \
    "mkdir -p '${stands_tooling_directory}/remote'"
  scp "${scp_common_options[@]}" \
    "${remote_teardown_platform_script}" \
    "${ssh_target}:${stands_tooling_directory}/remote/"
  ssh "${ssh_common_options[@]}" "${ssh_target}" \
    "chmod +x '${stands_tooling_directory}/remote/vps-teardown-platform.sh'"
}

run_teardown_on_server() {
  local server_id="$1"
  local representative_environment teardown_stands stands_root stands_tooling_directory
  local remove_mr_stands=false remove_tooling

  representative_environment="$(platform_environment_first_for_server "${server_id}")"
  platform_ssh_use_environment "${representative_environment}"

  stands_root="$(platform_environment_require "${representative_environment}" "STANDS_ROOT")"
  stands_tooling_directory="$(platform_environment_require "${representative_environment}" "STANDS_TOOLING_DIRECTORY")"
  teardown_stands="$(collect_teardown_stands_for_server "${server_id}")"

  if server_teardown_includes_mr_stands "${server_id}"; then
    remove_mr_stands=true
  fi

  remove_tooling="${TEARDOWN_REMOVE_TOOLING:-true}"

  log_step "Teardown VPS ${ssh_target}"
  echo "  stands: ${teardown_stands:-<none>}  mr-preview dirs: ${remove_mr_stands}  tooling: ${remove_tooling}"

  if [[ -z "${teardown_stands}" && "${remove_mr_stands}" != true && "${remove_tooling}" != true ]]; then
    echo "  nothing to remove on this server"
    return 0
  fi

  upload_teardown_script_to_server "${stands_tooling_directory}"

  ssh "${ssh_common_options[@]}" "${ssh_target}" \
    "STANDS_ROOT='${stands_root}' \
STANDS_TOOLING_DIRECTORY='${stands_tooling_directory}' \
TEARDOWN_STANDS='${teardown_stands}' \
TEARDOWN_REMOVE_MR_STANDS='${remove_mr_stands}' \
TEARDOWN_REMOVE_TOOLING='${remove_tooling}' \
bash '${stands_tooling_directory}/remote/vps-teardown-platform.sh'"
}

main() {
  if [[ "${TEARDOWN_CONFIRM:-}" != yes ]]; then
    echo "This removes WireGuard stands and tooling from VPS hosts in .env.platform." >&2
    echo "GitHub environments and secrets are NOT deleted." >&2
    echo "Re-run with: TEARDOWN_CONFIRM=yes ./scripts/teardown-platform.sh" >&2
    exit 1
  fi

  if ! load_platform_config "${repository_root}"; then
    exit 1
  fi

  declare -A servers_processed=()
  local server_id environment_name

  log_step "teardown-platform"
  echo "Environments in scope: $(teardown_environment_list | paste -sd, -)"

  while IFS= read -r environment_name; do
    [[ -z "${environment_name}" ]] && continue
    server_id="$(platform_environment_server_identity "${environment_name}")"
    [[ -n "${servers_processed[${server_id}]:-}" ]] && continue
    run_teardown_on_server "${server_id}"
    servers_processed["${server_id}"]=1
  done < <(teardown_environment_list)

  log_step "Teardown finished"
  echo "DNS and GitHub settings were not changed. Remove records manually if needed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
