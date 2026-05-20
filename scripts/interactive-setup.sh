#!/usr/bin/env bash
## Local helper menu (Compose smoke, two-stack test). Platform setup is launchpad-only.
##
##   ./scripts/interactive-setup.sh

set -uo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

print_separator() {
  printf '%s\n' "────────────────────────────────────────"
}

cmd_launchpad() {
  print_separator
  exec "${repository_root}/scripts/launchpad-run.sh"
}

cmd_validate_compose() {
  print_separator
  echo "Validating Compose templates…"
  bash "${repository_root}/scripts/compose-config-check.sh"
}

cmd_prepare_local_smoke() {
  print_separator
  local example_path="${repository_root}/.env.local.example"
  local target_path="${repository_root}/.env.local"
  if [[ ! -f "${example_path}" ]]; then
    echo "Missing .env.local.example" >&2
    return 1
  fi
  if [[ -f "${target_path}" ]]; then
    read -r -p ".env.local already exists. Overwrite from example? [y/N] " confirm
    if [[ ! "${confirm:-}" =~ ^[yY] ]]; then
      echo "Skipping copy."
    else
      cp "${example_path}" "${target_path}"
      echo "Copied .env.local.example → .env.local"
    fi
  else
    cp "${example_path}" "${target_path}"
    echo "Copied .env.local.example → .env.local"
  fi
  read -r -p "Run smoke check now (starts Docker stack)? [y/N] " run_smoke
  if [[ "${run_smoke:-}" =~ ^[yY] ]]; then
    bash "${repository_root}/scripts/local-smoke-check.sh"
  fi
}

cmd_two_stack_test() {
  print_separator
  local primary_example="${repository_root}/.env.local.example"
  local secondary_example="${repository_root}/.env.local.stack-b.example"
  local primary_target="${repository_root}/.env.local"
  local secondary_target="${repository_root}/.env.local.stack-b"
  if [[ ! -f "${primary_target}" ]]; then
    cp "${primary_example}" "${primary_target}"
    echo "Created ${primary_target}"
  fi
  if [[ ! -f "${secondary_target}" ]]; then
    cp "${secondary_example}" "${secondary_target}"
    echo "Created ${secondary_target}"
  fi
  bash "${repository_root}/scripts/local-two-stacks-test.sh"
}

show_main_menu() {
  cat <<EOF

Repository root: ${repository_root}

Platform setup (GitHub + VPS stands): only ./scripts/launchpad-run.sh

Choose:
  1) Run launchpad (full platform setup from .env.platform)
  2) Validate Compose templates (docker compose config)
  3) Create/update .env.local from example + optional smoke check
  4) Two-stack local integration test (needs Docker)
  0) Exit

EOF
}

main() {
  echo "dockerfile-vpn — local helpers (platform setup = launchpad only)"
  while true; do
    show_main_menu
    read -r -p "Enter choice [0-4]: " choice
    case "${choice:-}" in
      1) cmd_launchpad ;;
      2) cmd_validate_compose ;;
      3) cmd_prepare_local_smoke ;;
      4) cmd_two_stack_test ;;
      0) echo "Bye."; exit 0 ;;
      *) echo "Unknown choice." ;;
    esac
  done
}

main "$@"
