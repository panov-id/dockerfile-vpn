#!/usr/bin/env bash
## Shell checks for scripts/lib/vps-docker.sh (no apt on CI — function presence only).

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/vps-docker.sh
source "${repository_root}/scripts/lib/vps-docker.sh"

for function_name in \
  vps_run_privileged \
  vps_is_debian_or_ubuntu \
  vps_docker_compose_is_available \
  vps_install_docker_via_apt \
  vps_ensure_unix_user_in_docker_group \
  vps_ensure_docker_installed; do
  if ! declare -F "${function_name}" >/dev/null; then
    echo "FAIL: missing function ${function_name}" >&2
    exit 1
  fi
done

echo "OK: vps-docker library functions defined"
