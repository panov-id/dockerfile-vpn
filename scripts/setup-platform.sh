#!/usr/bin/env bash
## One-shot setup from .env.platform — you only edit secrets in that file.
##
## Prerequisites (once):
##   cp .env.platform.example .env.platform   # fill SSH_* and STAND_DNS_ZONE
##   gh auth login                            # once, if not already
##
## Run:
##   ./scripts/setup-platform.sh
##
## Does: GitHub environments + secrets/variables, dev/test branches, VPS stands
## (dev, test, uat, production) via SSH, local compose validate.

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

# shellcheck source=lib/load-platform-config.sh
source "${repository_root}/scripts/lib/load-platform-config.sh"
load_platform_config "${repository_root}"

layout_script="${repository_root}/scripts/stand-layout.sh"
resolve_host_script="${repository_root}/scripts/stand-resolve-public-host.sh"
remote_deploy_script="${repository_root}/scripts/remote/vps-deploy-stand.sh"
remote_teardown_script="${repository_root}/scripts/remote/vps-teardown-stand.sh"

ssh_common_options=(-o StrictHostKeyChecking=accept-new -o BatchMode=yes -i "${SSH_PRIVATE_KEY_FILE}")
ssh_target="${SSH_USER}@${SSH_HOST}"
scp_common_options=(-o StrictHostKeyChecking=accept-new -i "${SSH_PRIVATE_KEY_FILE}")

log_step() {
  printf '\n=== %s ===\n' "$1"
}

require_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "Install GitHub CLI: https://cli.github.com/" >&2
    exit 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "Run once: gh auth login" >&2
    exit 1
  fi
}

github_ensure_environment() {
  local environment_name="$1"
  if gh api --method PUT "repos/${GITHUB_REPOSITORY_SLUG}/environments/${environment_name}" >/dev/null 2>&1; then
    echo "  environment: ${environment_name}"
  else
    echo "  failed to create environment ${environment_name} (need admin?)" >&2
    return 1
  fi
}

github_apply_ssh_secrets() {
  local environment_name="$1"
  gh secret set SSH_HOST --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" --body "${SSH_HOST}"
  gh secret set SSH_USER --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" --body "${SSH_USER}"
  gh secret set SSH_PRIVATE_KEY --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" < "${SSH_PRIVATE_KEY_FILE}"
}

github_apply_stand_variables() {
  local environment_name="$1"
  local deploy_directory="${2:-}"
  gh variable set STANDS_ROOT --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" --body "${STANDS_ROOT}"
  gh variable set STANDS_TOOLING_DIRECTORY --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" --body "${STANDS_TOOLING_DIRECTORY}"
  gh variable set STAND_DNS_ZONE --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" --body "${STAND_DNS_ZONE}"
  gh variable set GIT_REMOTE_URL --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" --body "${GIT_REMOTE_URL}"
  if [[ -n "${deploy_directory}" ]]; then
    gh variable set DEPLOY_DIRECTORY --repo "${GITHUB_REPOSITORY_SLUG}" --env "${environment_name}" --body "${deploy_directory}"
  fi
}

setup_github() {
  log_step "GitHub: environments, secrets, variables"
  require_gh

  local environment_name
  for environment_name in production uat dev test mr-preview; do
    github_ensure_environment "${environment_name}"
  done

  local production_directory="${STANDS_ROOT}/production"
  local uat_directory="${STANDS_ROOT}/uat"

  for environment_name in dev test mr-preview; do
    echo "Configuring ${environment_name} …"
    github_apply_ssh_secrets "${environment_name}"
    github_apply_stand_variables "${environment_name}"
  done

  echo "Configuring uat …"
  github_apply_ssh_secrets "uat"
  github_apply_stand_variables "uat" "${uat_directory}"

  echo "Configuring production …"
  github_apply_ssh_secrets "production"
  github_apply_stand_variables "production" "${production_directory}"

  echo "GitHub setup done for ${GITHUB_REPOSITORY_SLUG}"
}

upload_tooling_to_vps() {
  log_step "VPS: upload deploy scripts"
  ssh "${ssh_common_options[@]}" "${ssh_target}" "mkdir -p '${STANDS_TOOLING_DIRECTORY}/remote'"
  scp "${scp_common_options[@]}" \
    "${layout_script}" \
    "${resolve_host_script}" \
    "${ssh_target}:${STANDS_TOOLING_DIRECTORY}/"
  scp "${scp_common_options[@]}" \
    "${remote_deploy_script}" \
    "${remote_teardown_script}" \
    "${ssh_target}:${STANDS_TOOLING_DIRECTORY}/remote/"
  ssh "${ssh_common_options[@]}" "${ssh_target}" \
    "chmod +x '${STANDS_TOOLING_DIRECTORY}/stand-layout.sh' '${STANDS_TOOLING_DIRECTORY}/stand-resolve-public-host.sh' '${STANDS_TOOLING_DIRECTORY}/remote/vps-deploy-stand.sh' '${STANDS_TOOLING_DIRECTORY}/remote/vps-teardown-stand.sh'"
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

  local stands_list="${VPS_STANDS_TO_BOOTSTRAP//,/ }"
  local stand_type
  for stand_type in ${stands_list}; do
    stand_type="$(echo "${stand_type}" | tr -d ' ')"
    [[ -z "${stand_type}" ]] && continue
    case "${stand_type}" in
      dev|test|uat|production)
        run_remote_stand_deploy "${stand_type}" "${stand_type}"
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

setup_git_branches() {
  log_step "Git: ensure dev and test branches exist on origin"
  require_gh
  local base_ref
  base_ref="$(git -C "${repository_root}" rev-parse main 2>/dev/null || git -C "${repository_root}" rev-parse HEAD)"
  for branch_name in dev test; do
    if git -C "${repository_root}" ls-remote --exit-code origin "refs/heads/${branch_name}" >/dev/null 2>&1; then
      echo "  branch ${branch_name} already on origin"
    else
      echo "  pushing ${branch_name} from ${base_ref} …"
      git -C "${repository_root}" push origin "${base_ref}:refs/heads/${branch_name}"
    fi
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

  if [[ "${SETUP_GITHUB}" == true ]]; then
    setup_github
  fi

  if [[ "${SETUP_CREATE_BRANCHES}" == true ]]; then
    setup_git_branches
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

main "$@"
