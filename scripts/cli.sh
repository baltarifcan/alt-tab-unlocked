#!/usr/bin/env bash
# Entry point. ATU_ROOT defaults to the checkout this script lives in; set it
# explicitly to run the scripts from somewhere else.
#
# Runtime dependencies come from PATH: bash, git, curl, jq, sed, grep, diff and
# find. All but jq ship with macOS; jq comes from Homebrew.

set -euo pipefail

# Resolve symlinks before deriving the root. Putting a link to this script on
# PATH (~/.local/bin/alt-tab-unlocked -> .../scripts/cli.sh) is the normal way
# to install it, and dirname on the *link* would give the link's directory --
# ~/.local -- rather than the checkout, so every subcommand below would point
# at a path that does not exist.
_atu_self=${BASH_SOURCE[0]}
while [ -L "$_atu_self" ]; do
  _atu_link=$(readlink "$_atu_self")
  case "$_atu_link" in
    /*) _atu_self=$_atu_link ;;
    *)  _atu_self=$(dirname "$_atu_self")/$_atu_link ;;
  esac
done
: "${ATU_ROOT:=$(cd "$(dirname "$_atu_self")/.." && pwd)}"
unset _atu_self _atu_link
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
