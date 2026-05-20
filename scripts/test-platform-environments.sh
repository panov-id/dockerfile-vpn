#!/usr/bin/env bash
## Unit checks for platform-environments.sh (no network).

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/platform-environments.sh
source "${repository_root}/scripts/lib/platform-environments.sh"

assert_equals() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "${expected}" != "${actual}" ]]; then
    echo "FAIL ${label}: expected '${expected}', got '${actual}'" >&2
    exit 1
  fi
}

assert_equals "PRODUCTION" "$(platform_environment_name_to_prefix production)" "prefix production"
assert_equals "MR_PREVIEW" "$(platform_environment_name_to_prefix mr-preview)" "prefix mr-preview"

export SSH_HOST=legacy-should-fail
if platform_environment_reject_legacy_variables; then
  echo "FAIL: legacy SSH_HOST must be rejected" >&2
  exit 1
fi
unset SSH_HOST

export PLATFORM_ENVIRONMENTS=production,invalid-env
if platform_environment_validate_names; then
  echo "FAIL: invalid PLATFORM_ENVIRONMENTS must fail" >&2
  exit 1
fi
unset PLATFORM_ENVIRONMENTS

PLATFORM_ENVIRONMENTS=dev,production
export PLATFORM_ENVIRONMENTS
mapfile -t listed < <(platform_environment_list)
assert_equals "2" "${#listed[@]}" "list length"
assert_equals "dev" "${listed[0]}" "first env"
assert_equals "production" "${listed[1]}" "second env"

export DEV_SSH_HOST=10.0.0.1
export DEV_SSH_USER=deploy
export DEV_SSH_PRIVATE_KEY_HOST_PATH=/tmp/dev-key
export DEV_STANDS_ROOT=/srv/vpn
export DEV_STANDS_TOOLING_DIRECTORY=/srv/vpn/_tooling
export DEV_STAND_DNS_ZONE=dev.vpn.example.com
export DEV_BOOTSTRAP_STANDS=dev

export PRODUCTION_SSH_HOST=10.0.0.1
export PRODUCTION_SSH_USER=deploy
export PRODUCTION_SSH_PRIVATE_KEY_HOST_PATH=/tmp/dev-key
export PRODUCTION_STANDS_ROOT=/srv/vpn-prod
export PRODUCTION_STANDS_TOOLING_DIRECTORY=/srv/vpn-prod/_tooling
export PRODUCTION_STAND_DNS_ZONE=vpn.example.com
export PRODUCTION_BOOTSTRAP_STANDS=production

touch /tmp/dev-key /tmp/prod-key
chmod 600 /tmp/dev-key /tmp/prod-key

if platform_environment_validate_shared_server_layout; then
  echo "FAIL: same host with different STANDS_ROOT must fail validation" >&2
  exit 1
fi

export PRODUCTION_STANDS_ROOT=/srv/vpn
export PRODUCTION_STANDS_TOOLING_DIRECTORY=/srv/vpn/_tooling

if ! platform_environment_validate_all; then
  echo "FAIL: validate_all should pass" >&2
  exit 1
fi

if ! platform_environment_validate_shared_server_layout; then
  echo "FAIL: shared layout should pass when roots match on same host" >&2
  exit 1
fi

assert_equals "/srv/vpn/production" "$(platform_environment_deploy_directory production)" "deploy dir production"
assert_equals "" "$(platform_environment_deploy_directory dev)" "deploy dir dev empty"

rm -f /tmp/dev-key /tmp/prod-key

echo "OK: test-platform-environments.sh"
