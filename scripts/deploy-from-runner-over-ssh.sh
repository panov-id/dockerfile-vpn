#!/usr/bin/env bash
## Intended usage from CI after checkout at release tag:
##   bash scripts/deploy-from-runner-over-ssh.sh "<deploy_remote_directory_absolute_path>"
##
## Requires SSH agent or caller-supplied ssh/scp wrapper on PATH.

set -euo pipefail

readonly deploy_remote_directory="$1"

if [[ -z "${deploy_remote_directory}" ]]; then
  echo "usage: $0 <remote_deploy_directory_absolute_path>" >&2
  exit 1
fi

readonly ssh_target="${SSH_DEPLOY_TARGET:?Set SSH_DEPLOY_TARGET, example user@vpn.example.com}"

scp docker-compose.yml .env.example "${ssh_target}:${deploy_remote_directory}/"

ssh "${ssh_target}" bash -s -- "${deploy_remote_directory}" <<'REMOTE_SCRIPT'
set -euo pipefail
deploy_remote_directory="$1"
cd "${deploy_remote_directory}"
docker compose up -d --pull always
REMOTE_SCRIPT
