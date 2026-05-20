#!/usr/bin/env bash
## Read .platform.yaml (simple key fields, no YAML parser required).

read_platform_manifest_value() {
  local manifest_file="$1"
  local key_path="$2"
  local line value
  if [[ ! -f "${manifest_file}" ]]; then
    return 1
  fi
  case "${key_path}" in
    platform_launchpad.source)
      line="$(grep -E '^[[:space:]]*source:[[:space:]]*' "${manifest_file}" | head -1 || true)"
      ;;
    platform_launchpad.image)
      line="$(grep -E '^[[:space:]]*image:[[:space:]]*' "${manifest_file}" | head -1 || true)"
      ;;
    platform_launchpad.version)
      line="$(grep -E '^[[:space:]]*version:[[:space:]]*' "${manifest_file}" | head -1 || true)"
      ;;
    application.repository_slug)
      line="$(awk '/^application:/{flag=1;next} /^[a-z_]+:/{flag=0} flag && /^[[:space:]]*repository_slug:/{print;exit}' "${manifest_file}")"
      ;;
    observability_stand_enabled)
      line="$(grep -E '^observability_stand_enabled:[[:space:]]*' "${manifest_file}" | head -1 || true)"
      ;;
    *)
      return 1
      ;;
  esac
  [[ -z "${line}" ]] && return 1
  value="${line#*:}"
  value="$(echo "${value}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')"
  printf '%s' "${value}"
}

read_platform_manifest_environments_csv() {
  local manifest_file="$1"
  if [[ ! -f "${manifest_file}" ]]; then
    return 1
  fi
  awk '
    /^platform_environments:/ { in_list=1; next }
    in_list && /^[[:space:]]*-/ {
      gsub(/^[[:space:]]*-[[:space:]]*/, "")
      gsub(/["'\'']/, "")
      printf "%s%s", (count++ ? "," : ""), $0
      next
    }
    in_list && /^[^[:space:]#]/ { exit }
    END { }
  ' "${manifest_file}"
}

load_platform_manifest() {
  local repository_root="$1"
  local manifest_file="${repository_root}/.platform.yaml"
  PLATFORM_MANIFEST_FILE="${manifest_file}"
  PLATFORM_LAUNCHPAD_SOURCE="registry"
  PLATFORM_LAUNCHPAD_IMAGE="ghcr.io/panov-id/platform-launchpad"
  PLATFORM_LAUNCHPAD_VERSION="1.0.0"
  PLATFORM_OBSERVABILITY_STAND_ENABLED="false"

  if [[ -f "${manifest_file}" ]]; then
    local parsed
    parsed="$(read_platform_manifest_value "${manifest_file}" platform_launchpad.source || true)"
    [[ -n "${parsed}" ]] && PLATFORM_LAUNCHPAD_SOURCE="${parsed}"
    parsed="$(read_platform_manifest_value "${manifest_file}" platform_launchpad.image || true)"
    [[ -n "${parsed}" ]] && PLATFORM_LAUNCHPAD_IMAGE="${parsed}"
    parsed="$(read_platform_manifest_value "${manifest_file}" platform_launchpad.version || true)"
    [[ -n "${parsed}" ]] && PLATFORM_LAUNCHPAD_VERSION="${parsed}"
    parsed="$(read_platform_manifest_value "${manifest_file}" observability_stand_enabled || true)"
    [[ -n "${parsed}" ]] && PLATFORM_OBSERVABILITY_STAND_ENABLED="${parsed}"
    parsed="$(read_platform_manifest_environments_csv "${manifest_file}" || true)"
    [[ -n "${parsed}" ]] && PLATFORM_ENVIRONMENTS_FROM_MANIFEST="${parsed}"
  fi

  export PLATFORM_MANIFEST_FILE
  export PLATFORM_LAUNCHPAD_SOURCE PLATFORM_LAUNCHPAD_IMAGE PLATFORM_LAUNCHPAD_VERSION
  export PLATFORM_OBSERVABILITY_STAND_ENABLED PLATFORM_ENVIRONMENTS_FROM_MANIFEST
}
