#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

local_environment_file="${LOCAL_ENVIRONMENT_FILE:-${repository_root}/.env.local}"

if [[ ! -f "${local_environment_file}" ]]; then
  echo "Missing ${local_environment_file}. Copy .env.local.example to .env.local and edit." >&2
  exit 1
fi

docker compose \
  -f docker-compose.yml \
  -f docker-compose.local.yml \
  --env-file "${local_environment_file}" \
  logs -f "$@"
