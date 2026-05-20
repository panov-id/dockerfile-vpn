#!/usr/bin/env bash
## SSH deploy key helpers (launchpad + host checks).
## Deploy keys must have NO passphrase — launchpad and Actions cannot use ssh-agent.

assert_ssh_private_key_usable_without_passphrase() {
  local private_key_file="${1:?private key path}"
  if [[ ! -f "${private_key_file}" ]]; then
    echo "SSH private key not found: ${private_key_file}" >&2
    return 1
  fi
  if ! ssh-keygen -y -f "${private_key_file}" </dev/null >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

print_deploy_ssh_key_instructions() {
  cat >&2 <<'EOF'
Use a dedicated deploy key WITHOUT a passphrase (launchpad and GitHub Actions cannot prompt).

  ssh-keygen -t ed25519 -f ~/.ssh/vpn_deploy_ed25519 -N '' -C 'dockerfile-vpn-deploy'
  ssh-copy-id -i ~/.ssh/vpn_deploy_ed25519.pub USER@YOUR_VPS

In .env.platform:
  LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH=/home/you/.ssh/vpn_deploy_ed25519

Do NOT use your daily SSH key if it has a passphrase (ssh-agent on the laptop does not run inside Docker).

Full guide: docs/deploy-ssh-key.md
EOF
}

prepare_launchpad_ssh_private_key_copy() {
  local mounted_key_path="${1:?mounted key path}"
  local destination_path="${2:?destination path}"

  if [[ ! -f "${mounted_key_path}" ]]; then
    echo "Missing SSH key mount: ${mounted_key_path}" >&2
    return 1
  fi

  install -m 600 "${mounted_key_path}" "${destination_path}"

  if ! assert_ssh_private_key_usable_without_passphrase "${destination_path}"; then
    echo "SSH private key requires a passphrase or is invalid: ${mounted_key_path}" >&2
    print_deploy_ssh_key_instructions
    return 1
  fi
  return 0
}
