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
## Does: GitHub environments + secrets/variables, dev/test branches, VPS stands
## (dev, test, uat, production) via SSH, local compose validate.

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

ssh_common_options=(-o StrictHostKeyChecking=accept-new -o BatchMode=yes -i "${SSH_PRIVATE_KEY_FILE}")
ssh_target="${SSH_USER}@${SSH_HOST}"
scp_common_options=(-o StrictHostKeyChecking=accept-new -i "${SSH_PRIVATE_KEY_FILE}")

log_step() {
  printf '\n=== %s ===\n' "$1"
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
  github_secret_set SSH_HOST --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" --body "${SSH_HOST}"
  github_secret_set SSH_USER --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" --body "${SSH_USER}"
  github_secret_set SSH_PRIVATE_KEY --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" < "${SSH_PRIVATE_KEY_FILE}"
}

github_apply_stand_variables() {
  local environment_name="$1"
  local deploy_directory="${2:-}"
  github_variable_set STANDS_ROOT --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" --body "${STANDS_ROOT}"
  github_variable_set STANDS_TOOLING_DIRECTORY --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" --body "${STANDS_TOOLING_DIRECTORY}"
  github_variable_set STAND_DNS_ZONE --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" --body "${STAND_DNS_ZONE}"
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
  for environment_name in production uat dev test mr-preview; do
    if ! github_ensure_environment "${environment_name}"; then
      environment_failures+=("${environment_name}")
      if [[ "${SETUP_GITHUB_STRICT:-true}" == true ]]; then
        return 1
      fi
    fi
  done
  if [[ ${#environment_failures[@]} -gt 0 ]]; then
    echo "  skipped secrets for missing environments: ${environment_failures[*]}" >&2
    echo "  fix PAT or create environments in UI, then re-run ./scripts/launchpad-run.sh" >&2
    if [[ "${SETUP_GITHUB_STRICT:-true}" == true ]]; then
      return 1
    fi
  fi

  local production_directory="${STANDS_ROOT}/production"
  local uat_directory="${STANDS_ROOT}/uat"

  github_configure_environment_if_present() {
    local environment_name="$1"
    local deploy_directory="${2:-}"
    if [[ " ${environment_failures[*]} " == *" ${environment_name} "* ]]; then
      echo "  skip ${environment_name} (environment missing)"
      return 0
    fi
    echo "Configuring ${environment_name} …"
    github_apply_ssh_secrets "${environment_name}"
    github_apply_stand_variables "${environment_name}" "${deploy_directory}"
  }

  github_configure_environment_if_present "dev"
  github_configure_environment_if_present "test"
  github_configure_environment_if_present "mr-preview"

  github_configure_environment_if_present "uat" "${uat_directory}"
  github_configure_environment_if_present "production" "${production_directory}"

  echo "GitHub setup done for ${GITHUB_REPOSITORY_SLUG}"
}

upload_tooling_to_vps() {
  log_step "VPS: upload deploy scripts"
  ssh "${ssh_common_options[@]}" "${ssh_target}" \
    "mkdir -p '${STANDS_TOOLING_DIRECTORY}/remote' '${STANDS_TOOLING_DIRECTORY}/lib'"
  scp "${scp_common_options[@]}" \
    "${layout_script}" \
    "${resolve_host_script}" \
    "${ssh_target}:${STANDS_TOOLING_DIRECTORY}/"
  scp "${scp_common_options[@]}" \
    "${vps_docker_library_script}" \
    "${ssh_target}:${STANDS_TOOLING_DIRECTORY}/lib/"
  scp "${scp_common_options[@]}" \
    "${remote_deploy_script}" \
    "${remote_teardown_script}" \
    "${remote_ensure_docker_script}" \
    "${ssh_target}:${STANDS_TOOLING_DIRECTORY}/remote/"
  ssh "${ssh_common_options[@]}" "${ssh_target}" \
    "chmod +x '${STANDS_TOOLING_DIRECTORY}/stand-layout.sh' '${STANDS_TOOLING_DIRECTORY}/stand-resolve-public-host.sh' '${STANDS_TOOLING_DIRECTORY}/lib/vps-docker.sh' '${STANDS_TOOLING_DIRECTORY}/remote/vps-deploy-stand.sh' '${STANDS_TOOLING_DIRECTORY}/remote/vps-teardown-stand.sh' '${STANDS_TOOLING_DIRECTORY}/remote/vps-ensure-docker.sh'"
}

ensure_vps_docker_engine() {
  if [[ "${SETUP_VPS_INSTALL_DOCKER:-true}" != true ]]; then
    echo "  SETUP_VPS_INSTALL_DOCKER=false — skipping Docker install on VPS"
    return 0
  fi
  log_step "VPS: ensure Docker Engine + Compose (Debian/Ubuntu apt)"
  ssh "${ssh_common_options[@]}" "${ssh_target}" \
    "export STANDS_TOOLING_DIRECTORY='${STANDS_TOOLING_DIRECTORY}'; export VPS_DOCKER_DEPLOY_UNIX_USER='${SSH_USER}'; bash '${STANDS_TOOLING_DIRECTORY}/remote/vps-ensure-docker.sh'"
}

run_remote_stand_deploy() {
  local stand_type="$1"
  local git_ref="$2"
  local pull_request_number="${3:-}"

  export STAND_DNS_ZONE
  local public_host
  if [[ "${stand_type}" == mr ]]; then
    public_host="$(STAND_DNS_ZONE="${STAND_DNS_ZONE}" "${resolve_host_script}" mr "${pull_request_number}")"
  else
    public_host="$(STAND_DNS_ZONE="${STAND_DNS_ZONE}" "${resolve_host_script}" "${stand_type}")"
  fi

  log_step "VPS: deploy stand '${stand_type}' (${public_host})"

  local remote_command
  remote_command=$(cat <<EOF
set -euo pipefail
export STANDS_ROOT='${STANDS_ROOT}'
export STANDS_TOOLING_DIRECTORY='${STANDS_TOOLING_DIRECTORY}'
export STAND_TYPE='${stand_type}'
export GIT_REF='${git_ref}'
export GIT_REMOTE_URL='${GIT_REMOTE_URL}'
export WIREGUARD_SERVER_PUBLIC_HOST='${public_host}'
export STAND_DNS_ZONE='${STAND_DNS_ZONE}'
EOF
)
  if [[ "${stand_type}" == mr ]]; then
    remote_command+=$(printf "\nexport PULL_REQUEST_NUMBER='%s'" "${pull_request_number}")
  fi
  remote_command+=$'\nbash "${STANDS_TOOLING_DIRECTORY}/remote/vps-deploy-stand.sh"\n'

  ssh "${ssh_common_options[@]}" "${ssh_target}" "${remote_command}"
}

setup_vps() {
  upload_tooling_to_vps
  ensure_vps_docker_engine

  local stands_list="${VPS_STANDS_TO_BOOTSTRAP//,/ }"
  local stand_type
  for stand_type in ${stands_list}; do
    stand_type="$(echo "${stand_type}" | tr -d ' ')"
    [[ -z "${stand_type}" ]] && continue
    case "${stand_type}" in
      dev|test|uat|production)
        local git_ref="${stand_type}"
        if [[ "${stand_type}" == uat || "${stand_type}" == production ]]; then
          git_ref="main"
        fi
        run_remote_stand_deploy "${stand_type}" "${git_ref}"
        ;;
      *)
        echo "Unknown stand in VPS_STANDS_TO_BOOTSTRAP: ${stand_type}" >&2
        exit 1
        ;;
    esac
  done

  echo ""
  echo "DNS reminder: point *.${STAND_DNS_ZONE} and ${STAND_DNS_ZONE} to ${SSH_HOST}"
  echo "Open UDP ports from: ${layout_script} dev|test|mr <N> (and production/uat ports)"
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
  echo "dockerfile-vpn — setup-platform (from .env.platform)"
  echo "Repository: ${GITHUB_REPOSITORY_SLUG}"
  echo "VPS: ${ssh_target}  DNS zone: ${STAND_DNS_ZONE}  stands: ${VPS_STANDS_TO_BOOTSTRAP}"
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
  • DNS: wildcard *.${STAND_DNS_ZONE} → ${SSH_HOST}
  • Open UDP ports on cloud firewall (see docs/stands-on-one-vps.md)
  • Work on a feature branch → PR into dev → MR preview deploys automatically
  • Merge to dev → dev stand updates on push
  • Release on main → production / uat deploy

Config file: ${repository_root}/.env.platform (edit and re-run this script anytime)
EOF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
