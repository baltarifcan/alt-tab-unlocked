#!/usr/bin/env bash
# Entry point. The Nix wrapper sets ATU_ROOT and puts the runtime deps on PATH;
# running from a git checkout works too, ATU_ROOT just defaults to the checkout.

set -euo pipefail
: "${ATU_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export ATU_ROOT

usage() {
  cat <<'USAGE'
alt-tab-unlocked — build AltTab from pinned upstream source with the Pro gate removed

  install        build the pinned version and install it into /Applications
  build          build only; leaves the .app in the cache
  status         what is pinned vs what is installed (exit 1 if they differ)
  verify         re-run the GPLv3 licence check against the pinned commit
  update         bump the pin to the latest upstream release (needs a git checkout)
  signing-cert   create a stable self-signed identity so TCC grants survive rebuilds
  uninstall      remove the app, the receipt and the build cache

Everything it does rests on upstream being GPLv3. `verify` is what checks that,
and it runs automatically before every build. See README.md.
USAGE
}

cmd="${1:-}"; [ $# -gt 0 ] && shift || true
case "$cmd" in
  install)      exec "$ATU_ROOT/scripts/install.sh" "$@" ;;
  build)        exec "$ATU_ROOT/scripts/build.sh" "$@" ;;
  status)       exec "$ATU_ROOT/scripts/status.sh" "$@" ;;
  verify)       exec "$ATU_ROOT/scripts/verify-licence.sh" "$@" ;;
  update)       exec "$ATU_ROOT/scripts/update-pin.sh" "$@" ;;
  signing-cert) exec "$ATU_ROOT/scripts/signing-identity.sh" --create ;;
  uninstall)    exec "$ATU_ROOT/scripts/uninstall.sh" "$@" ;;
  ''|-h|--help|help) usage ;;
  *) printf 'unknown command: %s\n\n' "$cmd" >&2; usage >&2; exit 2 ;;
esac
