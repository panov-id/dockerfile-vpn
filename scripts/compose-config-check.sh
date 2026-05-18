#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${root}"

if docker compose version >/dev/null 2>&1; then
  docker compose --env-file .env.example config >/dev/null
  echo "docker compose config: ok (.env.example)"
  exit 0
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  docker compose --env-file .env.example config >/dev/null
  echo "docker compose config: ok (.env.example)"
  exit 0
fi

echo "docker compose not available locally — skipping compose-config-check." >&2
exit 0
