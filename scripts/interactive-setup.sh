#!/usr/bin/env bash
## Interactive menu after you clone or pull this repo.
## Runs locally on your machine; no secrets are written into Git — optional uploads use `gh` CLI only.
##
## Usage:
##   ./scripts/interactive-setup.sh
##
## Note: deploy workflows are GitHub Actions (not GitLab CI). For GitLab you would mirror steps in `.gitlab-ci.yml` separately.

set -uo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

repository_slug_from_origin() {
  local url
  if ! url="$(git remote get-url origin 2>/dev/null)"; then
    echo "panov-id/dockerfile-vpn"
    return
  fi
  url="${url%.git}"
  if [[ "${url}" == https://github.com/* ]]; then
    echo "${url#https://github.com/}"
    return
  fi
  if [[ "${url}" == git@* ]]; then
    echo "${url#*:}"
    return
  fi
  echo "panov-id/dockerfile-vpn"
}

REPO_SLUG="$(repository_slug_from_origin)"

print_separator() {
  printf '%s\n' "────────────────────────────────────────"
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

cmd_print_vps_checklist() {
  print_separator
  cat <<EOF
VPS with Git — interactive setup (recommended):

  git clone git@github.com:${REPO_SLUG}.git
  cd dockerfile-vpn
  ./scripts/server-setup-wizard.sh

Non-interactive alternative (Debian/Ubuntu, curl | sudo):

  curl -fsSL 'https://raw.githubusercontent.com/${REPO_SLUG}/main/scripts/vps-bootstrap.sh' | sudo \\
    VPS_DEPLOY_GIT_URL='git@github.com:${REPO_SLUG}.git' \\
    VPS_DEPLOY_DIRECTORY='/opt/dockerfile-vpn/production' \\
    bash

GitHub Actions deploy only runs git + compose in DEPLOY_DIRECTORY (no scp).

Repository slug: ${REPO_SLUG}
EOF
}

cmd_print_github_manual() {
  print_separator
  local base_url="https://github.com/${REPO_SLUG}"
  cat <<EOF
GitHub (this repo uses GitHub Actions, not GitLab CI):

  • Actions settings: ${base_url}/settings/actions
  • Environments:    ${base_url}/settings/environments

Create environments: production  and  uat

Per environment add Secrets:
  SSH_HOST           — VPS hostname or IP
  SSH_USER           — UNIX user for deploy (e.g. deploy)
  SSH_PRIVATE_KEY    — private key matching public key in that user's ~/.ssh/authorized_keys

Per environment add Variable:
  DEPLOY_DIRECTORY   — absolute path ending with / (e.g. /opt/dockerfile-vpn/production/)

Branch protection: ${base_url}/settings/branches  → protect main (require PR).

First deploy: publish a Release from a tag on main (pre-release → uat, stable → production).

Workflow file: .github/workflows/deploy-release.yml
EOF
}

cmd_github_create_environments() {
  print_separator
  if ! command -v gh >/dev/null 2>&1; then
    echo "Install GitHub CLI: https://cli.github.com/"
    return 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "Run: gh auth login"
    return 1
  fi
  local environment_name
  for environment_name in production uat; do
    echo "Creating environment '${environment_name}' on ${REPO_SLUG} …"
    if gh api --method PUT "repos/${REPO_SLUG}/environments/${environment_name}" >/dev/null 2>&1; then
      echo "  OK: ${environment_name}"
    else
      echo "  Failed (need repo admin?). Create '${environment_name}' manually in the UI." >&2
    fi
  done
}

cmd_github_push_secrets_one_environment() {
  print_separator
  if ! command -v gh >/dev/null 2>&1; then
    echo "Install GitHub CLI: https://cli.github.com/"
    return 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "Run: gh auth login"
    return 1
  fi
  local environment_name
  read -r -p "GitHub environment name [production]: " environment_name
  environment_name="${environment_name:-production}"
  local ssh_host ssh_user key_path deploy_directory

  read -r -p "SSH_HOST (VPS hostname or IP): " ssh_host
  read -r -p "SSH_USER: " ssh_user
  read -r -p "Path to SSH private key file on this machine: " key_path
  read -r -p "DEPLOY_DIRECTORY on VPS (e.g. /opt/dockerfile-vpn/production/): " deploy_directory

  if [[ -z "${ssh_host}" || -z "${ssh_user}" || -z "${key_path}" || -z "${deploy_directory}" ]]; then
    echo "All fields are required." >&2
    return 1
  fi
  if [[ ! -f "${key_path}" ]]; then
    echo "Key file not found: ${key_path}" >&2
    return 1
  fi

  echo "Uploading secrets to ${REPO_SLUG} environment '${environment_name}' …"
  gh secret set SSH_HOST --repo "${REPO_SLUG}" --env "${environment_name}" --body "${ssh_host}"
  gh secret set SSH_USER --repo "${REPO_SLUG}" --env "${environment_name}" --body "${ssh_user}"
  gh secret set SSH_PRIVATE_KEY --repo "${REPO_SLUG}" --env "${environment_name}" < "${key_path}"
  gh variable set DEPLOY_DIRECTORY --repo "${REPO_SLUG}" --env "${environment_name}" --body "${deploy_directory}"
  echo "Done. Repeat for the other environment (e.g. uat) with its DEPLOY_DIRECTORY."
}

show_main_menu() {
  cat <<EOF

Repository root: ${repository_root}
Detected GitHub repo slug: ${REPO_SLUG}

Choose:
  1) Validate Compose templates (docker compose config)
  2) Create/update .env.local from example + optional smoke check
  3) Two-stack local integration test (needs Docker)
  4) Print VPS checklist (SSH / directories / firewall)
  5) Print GitHub manual checklist (open Settings URLs)
  6) GitHub: create environments production + uat (needs gh + repo admin)
  7) GitHub: upload SSH secrets + DEPLOY_DIRECTORY variable for one environment (needs gh)
  0) Exit

EOF
}

main() {
  echo "dockerfile-vpn — interactive setup (GitHub Actions deploy)"
  while true; do
    show_main_menu
    read -r -p "Enter choice [0-7]: " choice
    case "${choice:-}" in
      1) cmd_validate_compose ;;
      2) cmd_prepare_local_smoke ;;
      3) cmd_two_stack_test ;;
      4) cmd_print_vps_checklist ;;
      5) cmd_print_github_manual ;;
      6) cmd_github_create_environments ;;
      7) cmd_github_push_secrets_one_environment ;;
      0) echo "Bye."; exit 0 ;;
      *) echo "Unknown choice." ;;
    esac
  done
}

main "$@"
