#!/usr/bin/env bash
## Run ON the VPS (via SSH from GitHub Actions). Provisions one stand directory:
## git checkout of a ref, .env from .env.example, docker compose up.
##
## Install layout on the server first (CI copies scripts to STANDS_TOOLING_DIRECTORY):
##   ${STANDS_TOOLING_DIRECTORY}/scripts/stand-layout.sh
##   ${STANDS_TOOLING_DIRECTORY}/scripts/remote/vps-deploy-stand.sh
##
## Required environment variables:
##   STANDS_ROOT              — e.g. /srv/vpn
##   STANDS_TOOLING_DIRECTORY — e.g. /srv/vpn/_tooling
##   STAND_TYPE               — dev | test | mr
##   GIT_REF                  — branch (dev, test) or unused for mr (uses merge ref)
##   WIREGUARD_SERVER_PUBLIC_HOST
##
## For STAND_TYPE=mr also set:
##   PULL_REQUEST_NUMBER
##
## Optional:
##   GIT_REMOTE_URL           — origin URL when creating a new clone
##   SKIP_COMPOSE_UP          — if "true", only checkout + .env

set -euo pipefail

stands_root="${STANDS_ROOT:?STANDS_ROOT is required}"
stands_tooling_directory="${STANDS_TOOLING_DIRECTORY:?STANDS_TOOLING_DIRECTORY is required}"
stand_type="${STAND_TYPE:?STAND_TYPE is required}"
git_ref="${GIT_REF:?GIT_REF is required}"
public_host="${WIREGUARD_SERVER_PUBLIC_HOST:?WIREGUARD_SERVER_PUBLIC_HOST is required}"
skip_compose_up="${SKIP_COMPOSE_UP:-false}"

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
layout_script="${script_directory}/../stand-layout.sh"
if [[ ! -f "${layout_script}" ]]; then
  layout_script="${stands_tooling_directory}/stand-layout.sh"
fi
if [[ ! -f "${layout_script}" ]]; then
  echo "missing stand-layout.sh (looked in ${script_directory}/.. and ${stands_tooling_directory}/)" >&2
  exit 1
fi

pull_request_number=""
if [[ "${stand_type}" == mr ]]; then
  pull_request_number="${PULL_REQUEST_NUMBER:?PULL_REQUEST_NUMBER is required for mr stands}"
  # shellcheck source=/dev/null
  eval "$("${layout_script}" mr "${pull_request_number}")"
else
  # shellcheck source=/dev/null
  eval "$("${layout_script}" "${stand_type}")"
fi

stands_root="${stands_root%/}"
stands_tooling_directory="${stands_tooling_directory%/}"
deploy_directory="${stands_root}/${STAND_DIRECTORY_SUFFIX}"
mkdir -p "${stands_root}"

echo "=== stand deploy: type=${stand_type} directory=${deploy_directory} ref=${git_ref} ==="

if [[ -f "${stands_tooling_directory}/remote/vps-ensure-docker.sh" ]]; then
  export STANDS_TOOLING_DIRECTORY="${stands_tooling_directory}"
  export VPS_DOCKER_DEPLOY_UNIX_USER="${VPS_DOCKER_DEPLOY_UNIX_USER:-$(id -un)}"
  bash "${stands_tooling_directory}/remote/vps-ensure-docker.sh"
fi

repository_origin_url="${GIT_REMOTE_URL:-}"
if [[ -z "${repository_origin_url}" ]] && [[ -d "${deploy_directory}/.git" ]]; then
  repository_origin_url="$(git -C "${deploy_directory}" remote get-url origin 2>/dev/null || true)"
fi

if [[ ! -d "${deploy_directory}/.git" ]]; then
  if [[ -z "${repository_origin_url}" ]]; then
    echo "Stand directory is not a git repo and GIT_REMOTE_URL is not set." >&2
    exit 1
  fi
  echo "Cloning into ${deploy_directory} …"
  git clone "${repository_origin_url}" "${deploy_directory}"
fi

cd "${deploy_directory}"
git config --global --add safe.directory "${deploy_directory}"
if [[ -n "${repository_origin_url}" ]]; then
  git remote set-url origin "${repository_origin_url}" 2>/dev/null || git remote add origin "${repository_origin_url}"
fi

git fetch origin --prune

if [[ "${stand_type}" == mr ]]; then
  merge_local_branch="mr-${pull_request_number}-merge"
  git fetch origin "+refs/pull/${pull_request_number}/merge:refs/heads/${merge_local_branch}"
  git checkout "${merge_local_branch}"
else
  git checkout "${git_ref}" 2>/dev/null || git checkout -b "${git_ref}" "origin/${git_ref}"
  git pull --ff-only origin "${git_ref}" || true
fi

if [[ ! -f docker-compose.yml ]]; then
  echo "No docker-compose.yml in ${deploy_directory}" >&2
  exit 1
fi

if [[ ! -f .env.example ]]; then
  echo "No .env.example in ${deploy_directory}" >&2
  exit 1
fi

if [[ ! -f .env ]]; then
  cp .env.example .env
fi

apply_env_key() {
  local key="$1"
  local value="$2"
  if command -v python3 >/dev/null 2>&1; then
    DEPLOY_ENV_FILE=".env" DEPLOY_ENV_KEY="${key}" DEPLOY_ENV_VALUE="${value}" python3 <<'PY'
import os
path = os.environ["DEPLOY_ENV_FILE"]
key = os.environ["DEPLOY_ENV_KEY"]
val = os.environ["DEPLOY_ENV_VALUE"]
with open(path, encoding="utf-8") as handle:
    lines = handle.read().splitlines()
out = []
seen = False
for line in lines:
    if line.startswith(key + "="):
        out.append(key + "=" + val)
        seen = True
    else:
        out.append(line)
if not seen:
    out.append(key + "=" + val)
with open(path, "w", encoding="utf-8") as handle:
    handle.write("\n".join(out) + "\n")
PY
  else
    echo "python3 required to update .env" >&2
    exit 1
  fi
}

apply_env_key "COMPOSE_PROJECT_NAME" "${COMPOSE_PROJECT_NAME}"
apply_env_key "WIREGUARD_SERVER_PORT" "${WIREGUARD_SERVER_PORT}"
apply_env_key "WIREGUARD_INTERNAL_SUBNET" "${WIREGUARD_INTERNAL_SUBNET}"
apply_env_key "WIREGUARD_SERVER_PUBLIC_HOST" "${public_host}"

echo "=== .env stand keys ==="
grep -E '^(COMPOSE_PROJECT_NAME|WIREGUARD_SERVER_PORT|WIREGUARD_INTERNAL_SUBNET|WIREGUARD_SERVER_PUBLIC_HOST)=' .env || true

if [[ "${skip_compose_up}" == "true" ]]; then
  echo "SKIP_COMPOSE_UP=true — not running docker compose up"
  exit 0
fi

docker compose up -d --pull always
docker compose ps

echo "=== stand deploy finished: ${deploy_directory} ==="
