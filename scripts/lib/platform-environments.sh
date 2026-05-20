#!/usr/bin/env bash
## Per-GitHub-environment settings from .env.platform (no global SSH_HOST fallback).
##
## Variable naming: {PREFIX}_{FIELD}
##   production  → PRODUCTION_SSH_HOST, PRODUCTION_STANDS_ROOT, …
##   mr-preview  → MR_PREVIEW_SSH_HOST, …
##
## Required per listed environment in PLATFORM_ENVIRONMENTS:
##   SSH_HOST, SSH_USER, SSH_PRIVATE_KEY_HOST_PATH, STANDS_ROOT,
##   STANDS_TOOLING_DIRECTORY, STAND_DNS_ZONE
## Optional:
##   BOOTSTRAP_STANDS — comma list (dev,test,uat,production) for launchpad VPS bootstrap;
##                      empty = skip stand deploy on that server (typical for mr-preview).

platform_environment_default_names() {
  printf '%s\n' production uat dev test mr-preview
}

platform_environment_name_to_prefix() {
  local environment_name="$1"
  printf '%s' "${environment_name}" | tr '[:lower:]-' '[:upper:]_'
}

platform_environment_list() {
  local configured="${PLATFORM_ENVIRONMENTS:-}"
  if [[ -z "${configured}" ]]; then
    platform_environment_default_names
    return 0
  fi
  local item
  local normalized="${configured//,/ }"
  for item in ${normalized}; do
    item="$(echo "${item}" | tr -d ' ')"
    [[ -n "${item}" ]] && printf '%s\n' "${item}"
  done
}

platform_environment_variable_name() {
  local environment_name="$1"
  local field_name="$2"
  local prefix
  prefix="$(platform_environment_name_to_prefix "${environment_name}")"
  printf '%s_%s' "${prefix}" "${field_name}"
}

platform_environment_get() {
  local environment_name="$1"
  local field_name="$2"
  local variable_name
  variable_name="$(platform_environment_variable_name "${environment_name}" "${field_name}")"
  # shellcheck disable=SC2154  # set by caller after sourcing .env.platform
  printf '%s' "${!variable_name:-}"
}

platform_environment_require() {
  local environment_name="$1"
  local field_name="$2"
  local value
  value="$(platform_environment_get "${environment_name}" "${field_name}")"
  if [[ -z "${value}" ]]; then
    local variable_name
    variable_name="$(platform_environment_variable_name "${environment_name}" "${field_name}")"
    echo "Set ${variable_name} in .env.platform (GitHub environment: ${environment_name})." >&2
    return 1
  fi
  printf '%s' "${value}"
}

platform_environment_expand_home_path() {
  local path_value="$1"
  printf '%s' "${path_value/#\~/${HOME}}"
}

platform_environment_ssh_private_key_host_path() {
  local environment_name="$1"
  local path_value
  path_value="$(platform_environment_require "${environment_name}" "SSH_PRIVATE_KEY_HOST_PATH")"
  platform_environment_expand_home_path "${path_value}"
}

platform_environment_ssh_private_key_file() {
  local environment_name="$1"
  if [[ "${LAUNCHPAD_CONTAINER:-}" == true ]]; then
    printf '/run/launchpad/keys/%s' "${environment_name}"
    return 0
  fi
  platform_environment_ssh_private_key_host_path "${environment_name}"
}

platform_environment_bootstrap_stands() {
  local environment_name="$1"
  local value
  value="$(platform_environment_get "${environment_name}" "BOOTSTRAP_STANDS")"
  printf '%s' "${value}"
}

platform_environment_deploy_directory() {
  local environment_name="$1"
  local stands_root
  stands_root="$(platform_environment_require "${environment_name}" "STANDS_ROOT")"
  stands_root="${stands_root%/}"
  case "${environment_name}" in
    production) printf '%s/production' "${stands_root}" ;;
    uat) printf '%s/uat' "${stands_root}" ;;
    *) printf '%s' "" ;;
  esac
}

platform_environment_validate_all() {
  local environment_name
  local field_name
  local required_fields=(
    SSH_HOST
    SSH_USER
    SSH_PRIVATE_KEY_HOST_PATH
    STANDS_ROOT
    STANDS_TOOLING_DIRECTORY
    STAND_DNS_ZONE
  )
  local failures=0

  while IFS= read -r environment_name; do
    [[ -z "${environment_name}" ]] && continue
    for field_name in "${required_fields[@]}"; do
      if ! platform_environment_require "${environment_name}" "${field_name}" >/dev/null; then
        failures=$((failures + 1))
      fi
    done
    local key_path
    key_path="$(platform_environment_ssh_private_key_host_path "${environment_name}" 2>/dev/null || true)"
    if [[ -n "${key_path}" && ! -f "${key_path}" ]]; then
      echo "SSH private key not found for ${environment_name}: ${key_path}" >&2
      failures=$((failures + 1))
    fi
  done < <(platform_environment_list)

  if [[ "${failures}" -gt 0 ]]; then
    return 1
  fi
  return 0
}

## Unique servers: SSH_HOST + SSH_USER + key path (for grouping VPS steps).
platform_environment_server_identity() {
  local environment_name="$1"
  local host user key_path
  host="$(platform_environment_require "${environment_name}" "SSH_HOST")"
  user="$(platform_environment_require "${environment_name}" "SSH_USER")"
  key_path="$(platform_environment_ssh_private_key_host_path "${environment_name}")"
  printf '%s|%s|%s' "${host}" "${user}" "${key_path}"
}

platform_environment_validate_shared_server_layout() {
  local environment_name
  declare -A server_stands_root=()
  declare -A server_tooling=()
  local server_id stands_root tooling_directory

  while IFS= read -r environment_name; do
    [[ -z "${environment_name}" ]] && continue
    server_id="$(platform_environment_server_identity "${environment_name}")"
    stands_root="$(platform_environment_require "${environment_name}" "STANDS_ROOT")"
    tooling_directory="$(platform_environment_require "${environment_name}" "STANDS_TOOLING_DIRECTORY")"
    if [[ -n "${server_stands_root[${server_id}]:-}" && "${server_stands_root[${server_id}]}" != "${stands_root}" ]]; then
      echo "Environments on the same VPS must use the same STANDS_ROOT (${server_id})." >&2
      return 1
    fi
    if [[ -n "${server_tooling[${server_id}]:-}" && "${server_tooling[${server_id}]}" != "${tooling_directory}" ]]; then
      echo "Environments on the same VPS must use the same STANDS_TOOLING_DIRECTORY (${server_id})." >&2
      return 1
    fi
    server_stands_root["${server_id}"]="${stands_root}"
    server_tooling["${server_id}"]="${tooling_directory}"
  done < <(platform_environment_list)
  return 0
}

## Print lines: server_id<TAB>environment_name (one row per environment).
platform_environment_list_server_bindings() {
  local environment_name server_id
  while IFS= read -r environment_name; do
    [[ -z "${environment_name}" ]] && continue
    server_id="$(platform_environment_server_identity "${environment_name}")"
    printf '%s\t%s\n' "${server_id}" "${environment_name}"
  done < <(platform_environment_list)
}

## First environment name for a server_id (for SSH target selection).
platform_environment_first_for_server() {
  local target_server_id="$1"
  local environment_name server_id
  while IFS= read -r environment_name; do
    [[ -z "${environment_name}" ]] && continue
    server_id="$(platform_environment_server_identity "${environment_name}")"
    if [[ "${server_id}" == "${target_server_id}" ]]; then
      printf '%s' "${environment_name}"
      return 0
    fi
  done < <(platform_environment_list)
  return 1
}
