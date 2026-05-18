#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${root}"

if docker compose version >/dev/null 2>&1; then
  docker compose --env-file .env.example config >/dev/null
  docker compose -f docker-compose.yml -f docker-compose.local.yml --env-file .env.local.example config >/dev/null
  docker compose -f docker-compose.yml -f docker-compose.local.yml --env-file .env.local.stack-b.example config >/dev/null
  echo "docker compose config: ok (production + local stack A + local stack B templates)"
  exit 0
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  docker compose --env-file .env.example config >/dev/null
  docker compose -f docker-compose.yml -f docker-compose.local.yml --env-file .env.local.example config >/dev/null
  docker compose -f docker-compose.yml -f docker-compose.local.yml --env-file .env.local.stack-b.example config >/dev/null
  echo "docker compose config: ok (production + local stack A + local stack B templates)"
  exit 0
fi

echo "docker compose not available locally — skipping compose-config-check." >&2
exit 0
