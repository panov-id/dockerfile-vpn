#!/usr/bin/env bash
## Unit checks for scripts/lib/ssh-deploy-key.sh (no VPS required).

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/ssh-deploy-key.sh
source "${repository_root}/scripts/lib/ssh-deploy-key.sh"

temporary_directory=""
cleanup() {
  [[ -n "${temporary_directory}" ]] && rm -rf "${temporary_directory}"
}
trap cleanup EXIT

temporary_directory="$(mktemp -d)"
encrypted_key="${temporary_directory}/encrypted"
plain_key="${temporary_directory}/plain"

ssh-keygen -t ed25519 -f "${encrypted_key}" -N 'test-passphrase-only' -q -C 'test-encrypted'
ssh-keygen -t ed25519 -f "${plain_key}" -N '' -q -C 'test-plain'

if assert_ssh_private_key_usable_without_passphrase "${encrypted_key}"; then
  echo "FAIL: encrypted key must not pass" >&2
  exit 1
fi
echo "OK: encrypted key rejected"

if ! assert_ssh_private_key_usable_without_passphrase "${plain_key}"; then
  echo "FAIL: plain key must pass" >&2
  exit 1
fi
echo "OK: plain key accepted"

mounted="${temporary_directory}/mounted"
destination="${temporary_directory}/copy"
cp "${plain_key}" "${mounted}"
chmod 644 "${mounted}"

if ! prepare_launchpad_ssh_private_key_copy "${mounted}" "${destination}"; then
  echo "FAIL: prepare copy from mounted key" >&2
  exit 1
fi
[[ "$(stat -c '%a' "${destination}")" == "600" ]] || {
  echo "FAIL: copy must be mode 600" >&2
  exit 1
}
echo "OK: prepare_launchpad_ssh_private_key_copy"

echo "All ssh-deploy-key tests passed."
