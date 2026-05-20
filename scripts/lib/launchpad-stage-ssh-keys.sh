#!/usr/bin/env bash
## Copy per-environment SSH private keys for launchpad container mounts.

stage_launchpad_ssh_keys() {
  local repository_root="${1:?repository root required}"
  local keys_directory="${repository_root}/.launchpad-keys-staging"
  local environment_name host_key_path destination_path

  rm -rf "${keys_directory}"
  mkdir -p "${keys_directory}"
  chmod 700 "${keys_directory}"

  while IFS= read -r environment_name; do
    [[ -z "${environment_name}" ]] && continue
    host_key_path="$(platform_environment_ssh_private_key_host_path "${environment_name}")"
    destination_path="${keys_directory}/${environment_name}"
    cp "${host_key_path}" "${destination_path}"
    chmod 600 "${destination_path}"
  done < <(platform_environment_list)

  export LAUNCHPAD_KEYS_DIRECTORY="${keys_directory}"
}
