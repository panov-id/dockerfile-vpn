#!/usr/bin/env bash
## Verify LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH before launchpad (host).
##
##   ./scripts/verify-deploy-ssh-key.sh

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

# shellcheck source=lib/load-platform-config.sh
source "${repository_root}/scripts/lib/load-platform-config.sh"
# shellcheck source=lib/ssh-deploy-key.sh
source "${repository_root}/scripts/lib/ssh-deploy-key.sh"

if ! load_platform_config "${repository_root}"; then
  exit 1
fi

private_key_path="${LAUNCHPAD_SSH_PRIVATE_KEY_HOST_PATH:-${SSH_PRIVATE_KEY_FILE:-}}"
private_key_path="${private_key_path/#\~/${HOME}}"

echo "=== verify-deploy-ssh-key ==="
echo "key:  ${private_key_path}"
echo "host: ${SSH_USER}@${SSH_HOST}"
echo ""

if [[ ! -f "${private_key_path}" ]]; then
  echo "FAIL: private key file not found." >&2
  exit 1
fi

if ! assert_ssh_private_key_usable_without_passphrase "${private_key_path}"; then
  echo "FAIL: key has a passphrase or is invalid." >&2
  print_deploy_ssh_key_instructions
  exit 1
fi
echo "OK: key readable without passphrase"

if ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
    -i "${private_key_path}" -o IdentitiesOnly=yes \
    "${SSH_USER}@${SSH_HOST}" "echo ok" 2>&1; then
  echo "OK: SSH login to VPS"
else
  echo "FAIL: SSH login (check authorized_keys, SSH_USER, firewall)" >&2
  exit 1
fi
