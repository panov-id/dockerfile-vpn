#!/usr/bin/env bash
## Manual mirror of CI deploy (GitHub Actions deploy-release.yml): upload nothing via scp —
## SSH to the VPS, checkout the release tag in an existing git clone, restart Compose.
##
## From your laptop (release tag must exist on origin):
##   export SSH_DEPLOY_TARGET='deploy@vpn.example.com'
##   ./scripts/deploy-from-runner-over-ssh.sh /opt/dockerfile-vpn/production v1.0.0

set -euo pipefail

readonly deploy_remote_directory="${1:-}"
readonly release_git_tag="${2:-}"

if [[ -z "${deploy_remote_directory}" || -z "${release_git_tag}" ]]; then
  echo "usage: $0 <deploy_remote_directory_absolute_path> <release_git_tag>" >&2
  exit 1
fi

readonly ssh_target="${SSH_DEPLOY_TARGET:?Set SSH_DEPLOY_TARGET, example user@vpn.example.com}"

ssh "${ssh_target}" bash -s -- "${deploy_remote_directory}" "${release_git_tag}" <<'REMOTE_SCRIPT'
set -euo pipefail
deploy_remote_directory="$1"
release_git_tag="$2"
deploy_remote_directory="${deploy_remote_directory%/}"
cd "${deploy_remote_directory}"
git config --global --add safe.directory "${deploy_remote_directory}"
git fetch origin --tags
git checkout "${release_git_tag}"
docker compose up -d --pull always
REMOTE_SCRIPT
