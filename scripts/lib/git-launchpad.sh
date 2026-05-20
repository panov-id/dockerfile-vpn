#!/usr/bin/env bash
## Git helpers for launchpad (mounted repo from host — different UID → safe.directory).

configure_git_for_mounted_repository() {
  local repository_root="${1:?}"
  if [[ ! -d "${repository_root}/.git" ]]; then
    return 0
  fi
  git config --global --add safe.directory "${repository_root}" 2>/dev/null || true
}

mask_git_remote_url() {
  sed -E 's#(x-access-token:)[^@]+#\1***#; s#(github_pat_[A-Za-z0-9_]+)[A-Za-z0-9_]+#\1***#; s#(ghp_[A-Za-z0-9]+)[A-Za-z0-9]+#\1***#'
}

build_github_https_remote_url() {
  local github_host="${GH_HOST:-github.com}"
  local token="${GITHUB_TOKEN:?}"
  local slug="${GITHUB_REPOSITORY_SLUG:?}"
  printf 'https://x-access-token:%s@%s/%s.git' "${token}" "${github_host}" "${slug}"
}
