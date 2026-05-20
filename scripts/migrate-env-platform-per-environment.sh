#!/usr/bin/env bash
## One-time: expand legacy .env.platform (global SSH_HOST) into per-environment blocks.
## Does not overwrite variables that are already set.
##
##   ./scripts/migrate-env-platform-per-environment.sh

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repository_root}/.env.platform"

if [[ ! -f "${config_file}" ]]; then
  echo "Missing ${config_file}" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${config_file}"

if [[ -z "${SSH_HOST:-}" ]]; then
  echo "No legacy SSH_HOST in .env.platform — nothing to migrate (already per-environment?)." >&2
  exit 0
fi

legacy_user="${SSH_USER:-root}"
legacy_key="${LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH:-${SSH_PRIVATE_KEY_FILE:-}}"
legacy_stands_root="${STANDS_ROOT:-/srv/vpn}"
legacy_tooling="${STANDS_TOOLING_DIRECTORY:-${legacy_stands_root}/_tooling}"
legacy_zone="${STAND_DNS_ZONE:-vpn.example.com}"
legacy_bootstrap="${VPS_STANDS_TO_BOOTSTRAP:-dev,test,uat,production}"

if [[ -z "${legacy_key}" ]]; then
  echo "Set SSH_HOST migration source: LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH or SSH_PRIVATE_KEY_FILE" >&2
  exit 1
fi

append_if_missing() {
  local variable_name="$1"
  local variable_value="$2"
  if grep -q "^${variable_name}=" "${config_file}" 2>/dev/null; then
    return 0
  fi
  printf '\n%s=%s\n' "${variable_name}" "${variable_value}" >> "${config_file}"
}

# shellcheck source=lib/platform-environments.sh
source "${repository_root}/scripts/lib/platform-environments.sh"

for environment_name in production uat dev test mr-preview; do
  prefix="$(platform_environment_name_to_prefix "${environment_name}")"

  append_if_missing "${prefix}_SSH_HOST" "${SSH_HOST}"
  append_if_missing "${prefix}_SSH_USER" "${legacy_user}"
  append_if_missing "${prefix}_SSH_PRIVATE_KEY_HOST_PATH" "${legacy_key}"
  append_if_missing "${prefix}_STANDS_ROOT" "${legacy_stands_root}"
  append_if_missing "${prefix}_STANDS_TOOLING_DIRECTORY" "${legacy_tooling}"
  append_if_missing "${prefix}_STAND_DNS_ZONE" "${legacy_zone}"

  case "${environment_name}" in
    production) bootstrap_stand="production" ;;
    uat) bootstrap_stand="uat" ;;
    dev) bootstrap_stand="dev" ;;
    test) bootstrap_stand="test" ;;
    mr-preview) bootstrap_stand="" ;;
  esac
  append_if_missing "${prefix}_BOOTSTRAP_STANDS" "${bootstrap_stand}"
done

append_if_missing "PLATFORM_ENVIRONMENTS" "production,uat,dev,test,mr-preview"

echo "Appended per-environment blocks to ${config_file}"
echo "Review the file, then remove legacy SSH_HOST / VPS_STANDS_TO_BOOTSTRAP lines if you no longer need them."
