#!/usr/bin/env bash
## Guard: full platform setup (GitHub + multi-stand VPS) is launchpad-only.

platform_require_launchpad_for_setup() {
  if [[ "${LAUNCHPAD_CONTAINER:-}" == true ]]; then
    return 0
  fi
  if [[ "${WIZARD_TEST_SKIP_PLATFORM_GUARD:-}" == true ]]; then
    return 0
  fi
  cat >&2 <<'EOF'
Platform setup (GitHub environments, secrets, dev/test/MR stands) runs only via:

  cp .env.platform.example .env.platform
  ./scripts/launchpad-run.sh

See docs/launchpad.md
EOF
  return 1
}
