#!/usr/bin/env bash
## Verify SSH_PRIVATE_KEY_HOST_PATH for every environment in .env.platform.
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

echo "=== verify-deploy-ssh-key (all environments) ==="
echo ""

local_environment_name
local_failures=0

while IFS= read -r local_environment_name; do
  [[ -z "${local_environment_name}" ]] && continue
  local private_key_path ssh_host ssh_user
  private_key_path="$(platform_environment_ssh_private_key_file "${local_environment_name}")"
  ssh_host="$(platform_environment_require "${local_environment_name}" "SSH_HOST")"
  ssh_user="$(platform_environment_require "${local_environment_name}" "SSH_USER")"

  echo "[${local_environment_name}]"
  echo "  key:  ${private_key_path}"
  echo "  host: ${ssh_user}@${ssh_host}"

  if [[ ! -f "${private_key_path}" ]]; then
    echo "  FAIL: private key file not found." >&2
    local_failures=$((local_failures + 1))
    echo ""
    continue
  fi

  if ! assert_ssh_private_key_usable_without_passphrase "${private_key_path}"; then
    echo "  FAIL: key has a passphrase or is invalid." >&2
    print_deploy_ssh_key_instructions
    local_failures=$((local_failures + 1))
    echo ""
    continue
  fi
  echo "  OK: key readable without passphrase"

  if ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
      -i "${private_key_path}" -o IdentitiesOnly=yes \
      "${ssh_user}@${ssh_host}" "echo ok" 2>&1; then
    echo "  OK: SSH login"
  else
    echo "  FAIL: SSH login (check authorized_keys, SSH_USER, firewall)" >&2
    local_failures=$((local_failures + 1))
  fi
  echo ""
done < <(platform_environment_list)

if [[ "${local_failures}" -gt 0 ]]; then
  exit 1
fi

echo "All environments passed."
