#!/usr/bin/env bash
## One-shot setup from .env.platform — you only edit secrets in that file.
##
## Prerequisites (once):
##   cp .env.platform.example .env.platform   # fill secrets
##
## Run (no gh on host — recommended):
##   ./scripts/launchpad-run.sh
##
## Or on host with gh installed:
##   ./scripts/setup-platform.sh
##
## Does: GitHub environments + secrets/variables (per-environment from .env.platform),
## dev/test branches, VPS stands via SSH, local compose validate.

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

# shellcheck source=lib/load-platform-config.sh
source "${repository_root}/scripts/lib/load-platform-config.sh"
# shellcheck source=lib/git-launchpad.sh
source "${repository_root}/scripts/lib/git-launchpad.sh"
load_platform_config "${repository_root}"

layout_script="${repository_root}/scripts/stand-layout.sh"
resolve_host_script="${repository_root}/scripts/stand-resolve-public-host.sh"
remote_deploy_script="${repository_root}/scripts/remote/vps-deploy-stand.sh"
remote_teardown_script="${repository_root}/scripts/remote/vps-teardown-stand.sh"
remote_ensure_docker_script="${repository_root}/scripts/remote/vps-ensure-docker.sh"
vps_docker_library_script="${repository_root}/scripts/lib/vps-docker.sh"
remote_teardown_platform_script="${repository_root}/scripts/remote/vps-teardown-platform.sh"

ssh_common_options=()
scp_common_options=()
ssh_target=""
active_platform_environment=""

log_step() {
  printf '\n=== %s ===\n' "$1"
}

platform_ssh_use_environment() {
  local environment_name="$1"
  local ssh_host ssh_user ssh_key_file
  ssh_host="$(platform_environment_require "${environment_name}" "SSH_HOST")"
  ssh_user="$(platform_environment_require "${environment_name}" "SSH_USER")"
  ssh_key_file="$(platform_environment_ssh_private_key_file "${environment_name}")"
  active_platform_environment="${environment_name}"
  ssh_common_options=(-o StrictHostKeyChecking=accept-new -o BatchMode=yes -i "${ssh_key_file}")
  scp_common_options=(-o StrictHostKeyChecking=accept-new -i "${ssh_key_file}")
  ssh_target="${ssh_user}@${ssh_host}"
}

ensure_gh_authenticated() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI (gh) not found. Use ./scripts/launchpad-run.sh instead." >&2
    exit 1
  fi
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    export GH_TOKEN="${GITHUB_TOKEN}"
    if [[ "${LAUNCHPAD_CONTAINER:-}" == true ]]; then
      if ! gh api user --jq .login >/dev/null 2>&1; then
        echo "GITHUB_TOKEN in .env.platform is invalid or lacks API access." >&2
        exit 1
      fi
      return 0
    fi
    echo "${GITHUB_TOKEN}" | gh auth login --with-token 2>/dev/null || true
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "Run: gh auth login   — or set GITHUB_TOKEN in .env.platform and use launchpad-run.sh" >&2
    exit 1
  fi
}

ensure_git_push_access() {
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    return
  fi
  local https_remote
  https_remote="$(build_github_https_remote_url)"
  export GIT_REMOTE_URL="${https_remote}"

  if [[ "${LAUNCHPAD_CONTAINER:-}" == true ]]; then
    echo "  GIT_REMOTE_URL set for VPS deploys (branches via gh api in container)"
    return 0
  fi

  configure_git_for_mounted_repository "${repository_root}"
  if git -C "${repository_root}" remote get-url origin >/dev/null 2>&1; then
    git -C "${repository_root}" remote set-url origin "${https_remote}"
  else
    git -C "${repository_root}" remote add origin "${https_remote}"
  fi
}

github_ensure_environment() {
  local environment_name="$1"
  if gh api "repos/${GITHUB_REPOSITORY_SLUG}/environments/${environment_name}" >/dev/null 2>&1; then
    echo "  environment: ${environment_name} (already exists)"
    return 0
  fi
  local api_output
  if api_output="$(gh api --method PUT "repos/${GITHUB_REPOSITORY_SLUG}/environments/${environment_name}" 2>&1)"; then
    echo "  environment: ${environment_name}"
    return 0
  fi
  echo "  failed to create environment ${environment_name}" >&2
  echo "${api_output}" >&2
  cat >&2 <<'EOF'
  → Fine-grained PAT: Administration = Read and write (repo dockerfile-vpn)
  → Classic PAT: scope "repo"
  → Or: GitHub → repo Settings → Environments → New (production, uat, dev, test, mr-preview)
EOF
  return 1
}

github_print_pat_secrets_help() {
  cat >&2 <<'EOF'
  PAT cannot write environment secrets (403 on secrets/public-key).
  Fine-grained token for dockerfile-vpn needs BOTH:
    • Administration → Read and write  (create Environments)
    • Secrets → Read and write         (SSH_HOST, SSH_PRIVATE_KEY, …)
  Also: Actions → Read and write (for environment Variables).
  Or classic PAT with scope "repo".
EOF
}

github_secret_set() {
  local command_output
  if command_output="$(gh secret set "$@" 2>&1)"; then
    return 0
  fi
  echo "${command_output}" >&2
  if [[ "${command_output}" == *"403"* ]] || [[ "${command_output}" == *"public key"* ]]; then
    github_print_pat_secrets_help
  fi
  return 1
}

github_variable_set() {
  local command_output
  if command_output="$(gh variable set "$@" 2>&1)"; then
    return 0
  fi
  echo "${command_output}" >&2
  if [[ "${command_output}" == *"403"* ]]; then
    cat >&2 <<'EOF'
  PAT cannot write environment variables. Fine-grained: Actions → Read and write.
EOF
  fi
  return 1
}

github_apply_ssh_secrets() {
  local environment_name="$1"
  local ssh_host ssh_user ssh_key_file
  ssh_host="$(platform_environment_require "${environment_name}" "SSH_HOST")"
  ssh_user="$(platform_environment_require "${environment_name}" "SSH_USER")"
  ssh_key_file="$(platform_environment_ssh_private_key_file "${environment_name}")"
  github_secret_set SSH_HOST --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" --body "${ssh_host}"
  github_secret_set SSH_USER --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" --body "${ssh_user}"
  github_secret_set SSH_PRIVATE_KEY --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" < "${ssh_key_file}"
}

github_apply_stand_variables() {
  local environment_name="$1"
  local stands_root stands_tooling_directory stand_dns_zone deploy_directory
  stands_root="$(platform_environment_require "${environment_name}" "STANDS_ROOT")"
  stands_tooling_directory="$(platform_environment_require "${environment_name}" "STANDS_TOOLING_DIRECTORY")"
  stand_dns_zone="$(platform_environment_require "${environment_name}" "STAND_DNS_ZONE")"
  deploy_directory="$(platform_environment_deploy_directory "${environment_name}" 2>/dev/null || true)"
  github_variable_set STANDS_ROOT --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" --body "${stands_root}"
  github_variable_set STANDS_TOOLING_DIRECTORY --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" --body "${stands_tooling_directory}"
  github_variable_set STAND_DNS_ZONE --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" --body "${stand_dns_zone}"
  github_variable_set GIT_REMOTE_URL --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" --body "${GIT_REMOTE_URL}"
  if [[ -n "${deploy_directory}" ]]; then
    github_variable_set DEPLOY_DIRECTORY --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" --body "${deploy_directory}"
  fi
}

setup_github() {
  log_step "GitHub: environments, secrets, variables"
  ensure_gh_authenticated

  local environment_name
  local environment_failures=()
  while IFS= read -r environment_name; do
    [[ -z "${environment_name}" ]] && continue
    if ! github_ensure_environment "${environment_name}"; then
      environment_failures+=("${environment_name}")
      if [[ "${SETUP_GITHUB_STRICT:-true}" == true ]]; then
        return 1
      fi
    fi
  done < <(platform_environment_list)
  if [[ ${#environment_failures[@]} -gt 0 ]]; then
    echo "  skipped secrets for missing environments: ${environment_failures[*]}" >&2
    echo "  fix PAT or create environments in UI, then re-run ./scripts/launchpad-run.sh" >&2
    if [[ "${SETUP_GITHUB_STRICT:-true}" == true ]]; then
      return 1
    fi
  fi

  github_configure_environment_if_present() {
    local environment_name="$1"
    if [[ " ${environment_failures[*]} " == *" ${environment_name} "* ]]; then
      echo "  skip ${environment_name} (environment missing)"
      return 0
    fi
    echo "Configuring ${environment_name} …"
    github_apply_ssh_secrets "${environment_name}"
    github_apply_stand_variables "${environment_name}"
  }

  while IFS= read -r environment_name; do
    [[ -z "${environment_name}" ]] && continue
    github_configure_environment_if_present "${environment_name}"
  done < <(platform_environment_list)

  echo "GitHub setup done for ${GITHUB_REPOSITORY_SLUG}"
}

upload_tooling_to_vps() {
  local stands_tooling_directory="$1"
  ssh "${ssh_common_options[@]}" "${ssh_target}" \
    "mkdir -p '${stands_tooling_directory}/remote' '${stands_tooling_directory}/lib'"
  scp "${scp_common_options[@]}" \
    "${layout_script}" \
    "${resolve_host_script}" \
    "${ssh_target}:${stands_tooling_directory}/"
  scp "${scp_common_options[@]}" \
    "${vps_docker_library_script}" \
    "${ssh_target}:${stands_tooling_directory}/lib/"
  scp "${scp_common_options[@]}" \
    "${remote_deploy_script}" \
    "${remote_teardown_script}" \
    "${remote_ensure_docker_script}" \
    "${remote_teardown_platform_script}" \
    "${ssh_target}:${stands_tooling_directory}/remote/"
  ssh "${ssh_common_options[@]}" "${ssh_target}" \
    "chmod +x '${stands_tooling_directory}/stand-layout.sh' '${stands_tooling_directory}/stand-resolve-public-host.sh' '${stands_tooling_directory}/lib/vps-docker.sh' '${stands_tooling_directory}/remote/vps-deploy-stand.sh' '${stands_tooling_directory}/remote/vps-teardown-stand.sh' '${stands_tooling_directory}/remote/vps-ensure-docker.sh' '${stands_tooling_directory}/remote/vps-teardown-platform.sh'"
}

ensure_vps_docker_engine() {
  local environment_name="$1"
  local stands_tooling_directory ssh_user
  if [[ "${SETUP_VPS_INSTALL_DOCKER:-true}" != true ]]; then
    echo "  SETUP_VPS_INSTALL_DOCKER=false — skipping Docker install on VPS"
    return 0
  fi
  stands_tooling_directory="$(platform_environment_require "${environment_name}" "STANDS_TOOLING_DIRECTORY")"
  ssh_user="$(platform_environment_require "${environment_name}" "SSH_USER")"
  log_step "VPS [${environment_name}]: ensure Docker Engine + Compose (${ssh_target})"
  ssh "${ssh_common_options[@]}" "${ssh_target}" \
    "export STANDS_TOOLING_DIRECTORY='${stands_tooling_directory}'; export VPS_DOCKER_DEPLOY_UNIX_USER='${ssh_user}'; bash '${stands_tooling_directory}/remote/vps-ensure-docker.sh'"
}

run_remote_stand_deploy() {
  local environment_name="$1"
  local stand_type="$2"
  local git_ref="$3"
  local pull_request_number="${4:-}"

  platform_ssh_use_environment "${environment_name}"

  local stands_root stands_tooling_directory stand_dns_zone
  stands_root="$(platform_environment_require "${environment_name}" "STANDS_ROOT")"
  stands_tooling_directory="$(platform_environment_require "${environment_name}" "STANDS_TOOLING_DIRECTORY")"
  stand_dns_zone="$(platform_environment_require "${environment_name}" "STAND_DNS_ZONE")"

  local public_host
  if [[ "${stand_type}" == mr ]]; then
    public_host="$(STAND_DNS_ZONE="${stand_dns_zone}" "${resolve_host_script}" mr "${pull_request_number}")"
  else
    public_host="$(STAND_DNS_ZONE="${stand_dns_zone}" "${resolve_host_script}" "${stand_type}")"
  fi

  log_step "VPS [${environment_name}]: deploy stand '${stand_type}' (${public_host}) on ${ssh_target}"

  local remote_command
  remote_command=$(cat <<EOF
set -euo pipefail
export STANDS_ROOT='${stands_root}'
export STANDS_TOOLING_DIRECTORY='${stands_tooling_directory}'
export STAND_TYPE='${stand_type}'
export GIT_REF='${git_ref}'
export GIT_REMOTE_URL='${GIT_REMOTE_URL}'
export WIREGUARD_SERVER_PUBLIC_HOST='${public_host}'
export STAND_DNS_ZONE='${stand_dns_zone}'
EOF
)
  if [[ "${stand_type}" == mr ]]; then
    remote_command+=$(printf "\nexport PULL_REQUEST_NUMBER='%s'" "${pull_request_number}")
  fi
  remote_command+=$'\nbash "${stands_tooling_directory}/remote/vps-deploy-stand.sh"\n'

  ssh "${ssh_common_options[@]}" "${ssh_target}" "${remote_command}"
}

bootstrap_stands_for_environment() {
  local environment_name="$1"
  local bootstrap_stands="${2:-}"
  local stands_list stand_type git_ref

  bootstrap_stands="${bootstrap_stands//,/ }"
  [[ -z "${bootstrap_stands// }" ]] && return 0

  for stand_type in ${bootstrap_stands}; do
    stand_type="$(echo "${stand_type}" | tr -d ' ')"
    [[ -z "${stand_type}" ]] && continue
    case "${stand_type}" in
      dev|test|uat|production)
        git_ref="${stand_type}"
        if [[ "${stand_type}" == uat || "${stand_type}" == production ]]; then
          git_ref="main"
        fi
        run_remote_stand_deploy "${environment_name}" "${stand_type}" "${git_ref}"
        ;;
      *)
        echo "Unknown stand in ${environment_name} BOOTSTRAP_STANDS: ${stand_type}" >&2
        exit 1
        ;;
    esac
  done
}

setup_vps_for_server() {
  local server_id="$1"
  local representative_environment
  representative_environment="$(platform_environment_first_for_server "${server_id}")"
  platform_ssh_use_environment "${representative_environment}"

  local stands_tooling_directory
  stands_tooling_directory="$(platform_environment_require "${representative_environment}" "STANDS_TOOLING_DIRECTORY")"

  log_step "VPS server ${ssh_target} (via environment ${representative_environment})"
  upload_tooling_to_vps "${stands_tooling_directory}"
  ensure_vps_docker_engine "${representative_environment}"
}

setup_vps() {
  declare -A vps_servers_prepared=()
  local server_id environment_name bootstrap_stands

  while IFS=$'\t' read -r server_id environment_name; do
    [[ -z "${server_id}" ]] && continue
    if [[ -z "${vps_servers_prepared[${server_id}]:-}" ]]; then
      setup_vps_for_server "${server_id}"
      vps_servers_prepared["${server_id}"]=1
    fi
    bootstrap_stands="$(platform_environment_bootstrap_stands "${environment_name}")"
    bootstrap_stands_for_environment "${environment_name}" "${bootstrap_stands}"
  done < <(platform_environment_list_server_bindings)

  echo ""
  echo "DNS reminder (per environment):"
  while IFS= read -r environment_name; do
    [[ -z "${environment_name}" ]] && continue
    echo "  ${environment_name}: *.$(platform_environment_require "${environment_name}" STAND_DNS_ZONE) and apex → $(platform_environment_require "${environment_name}" SSH_HOST)"
  done < <(platform_environment_list)
  echo "Open UDP ports: ${layout_script} dev|test|mr <N> (see docs/stands-on-one-vps.md)"
}

create_branch_on_origin() {
  local branch_name="$1"
  local main_sha="$2"
  local base_ref="$3"

  if gh api "repos/${GITHUB_REPOSITORY_SLUG}/git/ref/heads/${branch_name}" >/dev/null 2>&1; then
    echo "  branch ${branch_name} already on origin (API)"
    return 0
  fi

  echo "  creating ${branch_name} …"

  if [[ "${LAUNCHPAD_CONTAINER:-}" != true ]] && [[ -d "${repository_root}/.git" ]]; then
    configure_git_for_mounted_repository "${repository_root}"
    if git -C "${repository_root}" push origin "${base_ref}:refs/heads/${branch_name}" 2>&1; then
      echo "  OK: git push ${branch_name}"
      return 0
    fi
    echo "  git push failed for ${branch_name}, trying gh api …" >&2
  fi

  local api_output
  if api_output="$(gh api --method POST "repos/${GITHUB_REPOSITORY_SLUG}/git/refs" \
      -f "ref=refs/heads/${branch_name}" -f "sha=${main_sha}" 2>&1)"; then
    echo "  OK: gh api created refs/heads/${branch_name}"
    return 0
  fi

  echo "${api_output}" >&2
  if [[ "${api_output}" == *"403"* ]] || [[ "${api_output}" == *"not accessible"* ]]; then
    cat >&2 <<'EOF'
  PAT cannot create git refs. Fix GITHUB_TOKEN on https://github.com/settings/tokens:
    • Fine-grained: repo dockerfile-vpn → Contents = Read and write
    • Or classic PAT: scope repo (full control of private repositories)
    • If org uses SSO: open the token → Configure SSO → Authorize for panov-id
  Or create branches manually: GitHub → Branches → New branch (dev, test from main).
EOF
  fi
  echo "  FAILED to create branch ${branch_name}" >&2
  return 1
}

setup_git_branches() {
  log_step "Git: ensure dev and test branches exist on origin"
  ensure_gh_authenticated
  ensure_git_push_access

  local github_host="${GH_HOST:-github.com}"
  echo "  host: ${github_host}  repo: ${GITHUB_REPOSITORY_SLUG}"
  if [[ "${LAUNCHPAD_CONTAINER:-}" == true ]]; then
    echo "  mode: create branches via gh api (mounted repo may skip git push)"
  else
    local origin_display
    origin_display="$(git -C "${repository_root}" remote get-url origin 2>/dev/null | mask_git_remote_url || echo '<no origin>')"
    echo "  origin: ${origin_display}"
  fi

  local base_ref=""
  if [[ "${LAUNCHPAD_CONTAINER:-}" != true ]] && [[ -d "${repository_root}/.git" ]]; then
    configure_git_for_mounted_repository "${repository_root}"
    base_ref="$(git -C "${repository_root}" rev-parse main 2>/dev/null || git -C "${repository_root}" rev-parse HEAD 2>/dev/null || true)"
    if [[ -n "${base_ref}" ]]; then
      echo "  local base ref: ${base_ref}"
    fi
  fi

  local main_sha
  if ! main_sha="$(gh api "repos/${GITHUB_REPOSITORY_SLUG}/git/ref/heads/main" --jq .object.sha 2>&1)"; then
    echo "  ERROR reading main via gh api: ${main_sha}" >&2
    echo "  Fix GH_HOST / GITHUB_REPOSITORY_SLUG / GITHUB_TOKEN, then: ./scripts/launchpad-diagnose-git.sh" >&2
    return 1
  fi
  echo "  main SHA: ${main_sha}"

  local branch_name
  for branch_name in dev test; do
    create_branch_on_origin "${branch_name}" "${main_sha}" "${base_ref:-${main_sha}}"
  done
}

run_local_compose_check() {
  log_step "Local: docker compose config check"
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    bash "${repository_root}/scripts/compose-config-check.sh"
  else
    echo "Docker not available — skipped (CI will validate on PR)."
  fi
}

main() {
  local environment_name
  echo "dockerfile-vpn — setup-platform (from .env.platform)"
  echo "Repository: ${GITHUB_REPOSITORY_SLUG}"
  echo "GitHub environments:"
  while IFS= read -r environment_name; do
    [[ -z "${environment_name}" ]] && continue
    echo "  ${environment_name}: $(platform_environment_require "${environment_name}" SSH_USER)@$(platform_environment_require "${environment_name}" SSH_HOST) bootstrap=[$(platform_environment_bootstrap_stands "${environment_name}")]"
  done < <(platform_environment_list)
  echo "Steps: SETUP_CREATE_BRANCHES=${SETUP_CREATE_BRANCHES} SETUP_GITHUB=${SETUP_GITHUB} SETUP_VPS=${SETUP_VPS} SETUP_LOCAL_COMPOSE_CHECK=${SETUP_LOCAL_COMPOSE_CHECK}"

  # Branches first: setup_github can fail (secrets/admin) and must not skip dev/test
  # (launchpad-diagnose-git.sh --try-create only runs this block).
  if [[ "${SETUP_CREATE_BRANCHES}" == true ]]; then
    setup_git_branches
  fi

  if [[ "${SETUP_GITHUB}" == true ]]; then
    setup_github
  fi

  if [[ "${SETUP_VPS}" == true ]]; then
    setup_vps
  fi

  if [[ "${SETUP_LOCAL_COMPOSE_CHECK}" == true ]]; then
    run_local_compose_check
  fi

  log_step "All done"
  cat <<EOF

Next steps (no scripts required):
  • DNS: point each environment's STAND_DNS_ZONE (and wildcard) to its SSH_HOST
  • Open UDP ports on cloud firewall (see docs/stands-on-one-vps.md)
  • Work on a feature branch → PR into dev → MR preview deploys automatically
  • Merge to dev → dev stand updates on push
  • Release on main → production / uat deploy
  • Teardown VPS: ./scripts/teardown-platform-run.sh

Config file: ${repository_root}/.env.platform (edit and re-run this script anytime)
EOF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
