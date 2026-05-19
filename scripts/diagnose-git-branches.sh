#!/usr/bin/env bash
## Read-only checks for dev/test branch creation (run inside launchpad or on host with gh).
##
##   ./scripts/launchpad-diagnose-git.sh
##
## Optional: attempt to create missing branches (same as setup-platform):
##   ./scripts/launchpad-diagnose-git.sh --try-create

set -euo pipefail

try_create=false
if [[ "${1:-}" == "--try-create" ]]; then
  try_create=true
fi

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

# shellcheck source=lib/load-platform-config.sh
source "${repository_root}/scripts/lib/load-platform-config.sh"
# shellcheck source=lib/git-launchpad.sh
source "${repository_root}/scripts/lib/git-launchpad.sh"
load_platform_config "${repository_root}" || exit 1

if [[ -d "${repository_root}/.git" ]]; then
  configure_git_for_mounted_repository "${repository_root}"
fi

github_host="${GH_HOST:-github.com}"
echo "=== diagnose-git-branches ==="
echo "host:              ${github_host}"
echo "repository:        ${GITHUB_REPOSITORY_SLUG}"
echo "GH_HOST:           ${GH_HOST:-<unset — gh uses github.com>}"
echo "GITHUB_API_URL:    ${GITHUB_API_URL:-<unset>}"
echo "SETUP_CREATE_BRANCHES: ${SETUP_CREATE_BRANCHES}"
echo ""

if ! command -v gh >/dev/null 2>&1; then
  echo "FAIL: gh not found. Run via ./scripts/launchpad-diagnose-git.sh (Docker)." >&2
  exit 1
fi

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  export GH_TOKEN="${GITHUB_TOKEN}"
fi

echo "--- gh auth status ---"
if ! gh auth status 2>&1; then
  echo "FAIL: gh not authenticated. Set GITHUB_TOKEN in .env.platform." >&2
  exit 1
fi
echo ""

echo "--- remote branches (gh api) ---"
if ! gh api "repos/${GITHUB_REPOSITORY_SLUG}/branches" --paginate --jq '.[].name' 2>&1; then
  echo "FAIL: cannot list branches. Typical causes:" >&2
  echo "  • wrong GITHUB_REPOSITORY_SLUG" >&2
  echo "  • wrong GH_HOST — for github.com leave GH_HOST unset in .env.platform" >&2
  echo "  • PAT missing repo Contents read" >&2
  exit 1
fi
echo ""

echo "--- main ref (gh api) ---"
main_sha=""
if ! main_sha="$(gh api "repos/${GITHUB_REPOSITORY_SLUG}/git/ref/heads/main" --jq .object.sha 2>&1)"; then
  echo "FAIL: ${main_sha}" >&2
  echo "  (no main branch or no access)" >&2
  exit 1
fi
echo "main SHA: ${main_sha}"
echo ""

for branch_name in dev test; do
  echo "--- branch: ${branch_name} ---"
  if gh api "repos/${GITHUB_REPOSITORY_SLUG}/git/ref/heads/${branch_name}" --jq .ref >/dev/null 2>&1; then
    echo "  exists on origin (API)"
  else
    echo "  MISSING on origin"
  fi
done
echo ""

if [[ -d "${repository_root}/.git" ]]; then
  echo "--- local git (optional in launchpad; branches use gh api) ---"
  echo "  HEAD: $(git -C "${repository_root}" rev-parse HEAD 2>/dev/null || echo '?')"
  if git -C "${repository_root}" remote get-url origin >/dev/null 2>&1; then
    echo "  origin: $(git -C "${repository_root}" remote get-url origin | mask_git_remote_url)"
    for branch_name in dev test; do
      if git -C "${repository_root}" ls-remote --exit-code origin "refs/heads/${branch_name}" >/dev/null 2>&1; then
        echo "  ls-remote ${branch_name}: found"
      else
        echo "  ls-remote ${branch_name}: not found"
      fi
    done
  else
    echo "  no origin remote"
  fi
  echo ""
else
  echo "--- local .git: not present (OK in minimal mounts) ---"
  echo ""
fi

echo "--- token probe ---"
if gh api "repos/${GITHUB_REPOSITORY_SLUG}" --jq .full_name >/dev/null 2>&1; then
  echo "  repo read: OK"
else
  echo "  repo read: FAIL" >&2
fi
if [[ "${try_create}" != true ]] && ! gh api "repos/${GITHUB_REPOSITORY_SLUG}/git/ref/heads/dev" >/dev/null 2>&1; then
  main_sha_probe="$(gh api "repos/${GITHUB_REPOSITORY_SLUG}/git/ref/heads/main" --jq .object.sha 2>/dev/null || true)"
  if [[ -n "${main_sha_probe}" ]]; then
    if gh api --method POST "repos/${GITHUB_REPOSITORY_SLUG}/git/refs" \
        -f "ref=refs/heads/__launchpad_write_probe" -f "sha=${main_sha_probe}" >/dev/null 2>&1; then
      echo "  repo write (Contents): OK"
      gh api --method DELETE "repos/${GITHUB_REPOSITORY_SLUG}/git/refs/heads/__launchpad_write_probe" >/dev/null 2>&1 || true
    else
      echo "  repo write (Contents): FAIL" >&2
      cat >&2 <<'EOF'
        → Fine-grained PAT: dockerfile-vpn → Contents = Read and write
        → Classic PAT: enable scope "repo"
        → Org SSO: token page → Configure SSO → Authorize panov-id
EOF
    fi
  fi
fi
echo ""

if [[ "${try_create}" != true ]]; then
  cat <<EOF
Done (read-only). To attempt creation:
  ./scripts/launchpad-diagnose-git.sh --try-create

Or re-run full setup (branches only):
  # in .env.platform temporarily:
  # SETUP_GITHUB=false
  # SETUP_VPS=false
  ./scripts/launchpad-run.sh

Save full launchpad log:
  ./scripts/launchpad-run.sh 2>&1 | tee /tmp/launchpad.log
  grep -E 'Git:|branch|push|error|FAIL|denied|403|401' /tmp/launchpad.log
EOF
  exit 0
fi

echo "=== --try-create: running setup_git_branches ==="
repository_root="${repository_root}" # used by setup-platform.sh
# shellcheck source=setup-platform.sh
source "${repository_root}/scripts/setup-platform.sh"
setup_git_branches

echo "=== after create: branch list ---"
gh api "repos/${GITHUB_REPOSITORY_SLUG}/branches" --jq '.[].name'
