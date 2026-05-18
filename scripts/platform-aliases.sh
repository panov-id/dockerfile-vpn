# Source from your shell (optional):
#   source /path/to/dockerfile-vpn/scripts/platform-aliases.sh
#
# Then run:  vpn-setup

if [[ -n "${BASH_VERSION:-}" ]]; then
  repository_root_aliases="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  alias vpn-setup="cd '${repository_root_aliases}' && ./scripts/setup-platform.sh"
  alias vpn-compose-check="cd '${repository_root_aliases}' && ./scripts/compose-config-check.sh"
  alias vpn-local-up="cd '${repository_root_aliases}' && ./scripts/local-compose-up.sh"
fi
