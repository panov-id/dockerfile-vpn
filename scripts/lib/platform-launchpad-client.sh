#!/usr/bin/env bash
## Run Platform Launchpad product against this application repository.

run_platform_launchpad() {
  local application_repository_root="$1"

  # shellcheck source=read-platform-manifest.sh
  source "${application_repository_root}/scripts/lib/read-platform-manifest.sh"
  load_platform_manifest "${application_repository_root}"

  if [[ -n "${PLATFORM_ENVIRONMENTS_FROM_MANIFEST:-}" ]]; then
    export PLATFORM_ENVIRONMENTS="${PLATFORM_ENVIRONMENTS_FROM_MANIFEST}"
  fi

  export APP_REPOSITORY_ROOT="${application_repository_root}"
  export PLATFORM_PRODUCT_VERSION="${PLATFORM_LAUNCHPAD_VERSION}"

  echo "Platform Launchpad ${PLATFORM_LAUNCHPAD_SOURCE} ${PLATFORM_LAUNCHPAD_IMAGE}:${PLATFORM_LAUNCHPAD_VERSION}"
  echo "Application root: ${APP_REPOSITORY_ROOT}"

  case "${PLATFORM_LAUNCHPAD_SOURCE}" in
    embedded)
      run_platform_launchpad_embedded "${application_repository_root}"
      ;;
    registry)
      run_platform_launchpad_registry "${application_repository_root}"
      ;;
    *)
      echo "Unknown platform_launchpad.source in .platform.yaml: ${PLATFORM_LAUNCHPAD_SOURCE}" >&2
      echo "  Use: embedded | registry" >&2
      return 1
      ;;
  esac
}

run_platform_launchpad_embedded() {
  local application_repository_root="$1"
  local export_root="${application_repository_root}/export/platform-launchpad"
  local compose_file

  if [[ -f "${export_root}/docker/docker-compose.launchpad.yml" ]]; then
    compose_file="${export_root}/docker/docker-compose.launchpad.yml"
  else
    compose_file="${application_repository_root}/docker/docker-compose.launchpad.yml"
    echo "Note: using in-repo launchpad (copy product to export/platform-launchpad for split)." >&2
  fi

  # shellcheck source=launchpad-preflight.sh
  source "${application_repository_root}/scripts/lib/launchpad-preflight.sh"
  launchpad_preflight_host "${application_repository_root}"

  export LAUNCHPAD_KEYS_DIRECTORY
  export APP_REPOSITORY_ROOT="${application_repository_root}"
  docker compose -f "${compose_file}" build launchpad
  docker compose -f "${compose_file}" run --rm \
    -e APP_REPOSITORY_ROOT="${application_repository_root}" \
    -e PLATFORM_PRODUCT_VERSION="${PLATFORM_LAUNCHPAD_VERSION}" \
    launchpad
}

run_platform_launchpad_registry() {
  local application_repository_root="$1"
  local image_reference="${PLATFORM_LAUNCHPAD_IMAGE}:${PLATFORM_LAUNCHPAD_VERSION}"

  # shellcheck source=launchpad-preflight.sh
  source "${application_repository_root}/scripts/lib/launchpad-preflight.sh"
  launchpad_preflight_host "${application_repository_root}"

  docker pull "${image_reference}"
  docker run --rm \
    -v "${application_repository_root}:/workspace/app:ro" \
    -v "${application_repository_root}/.env.platform:/workspace/.env.platform:ro" \
    -v "${LAUNCHPAD_KEYS_DIRECTORY}:/run/launchpad/keys:ro" \
    -e LAUNCHPAD_CONTAINER=true \
    -e APP_REPOSITORY_ROOT=/workspace/app \
    -e PLATFORM_PRODUCT_VERSION="${PLATFORM_LAUNCHPAD_VERSION}" \
    "${image_reference}"
}
