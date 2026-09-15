# Shared helpers. Sourced, never executed.

set -euo pipefail

# Set by the Nix wrapper to the store path; falls back to the checkout so the
# scripts are runnable straight out of a git clone.
: "${ATU_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export ATU_ROOT
[ -f "$ATU_ROOT/pin.json" ] || {
  printf 'ERROR ATU_ROOT=%s does not hold pin.json\n' "$ATU_ROOT" >&2; exit 1;
}

PIN="$ATU_ROOT/pin.json"
CACHE="${ATU_CACHE:-$HOME/.cache/alt-tab-unlocked}"
STATE="${ATU_STATE:-$HOME/.local/state/alt-tab-unlocked}"
SRC="$CACHE/src"
RECEIPT="$STATE/receipt.json"
APP_DIR="${ATU_APP_DIR:-/Applications}"
APP="$APP_DIR/AltTab.app"

# The system toolchain, never a nixpkgs shim. xcodebuild has to be the real one:
# the project is an .xcodeproj with local SwiftPM packages and a code-signing
# phase, none of which xcbuild reimplements.
XCODEBUILD=/usr/bin/xcodebuild

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
info()  { printf '  %s\n' "$*"; }
ok()    { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn()  { printf '  \033[33m!\033[0m %s\n' "$*" >&2; }
die()   { printf '\n\033[31mERROR\033[0m %s\n' "$*" >&2; exit 1; }

pin() { jq -re ".$1" "$PIN"; }

# Pick an Xcode to build with.
#
# Two traps here, both learned the hard way:
#
#   1. The licence is accepted per Xcode install, and `sudo xcodebuild -license
#      accept` applies it to whatever `xcode-select -p` currently points at —
#      which is not necessarily the one this script resolves. So the licence is
#      part of choosing, not a check bolted on afterwards.
#   2. Preference is for the App Store Xcode, because that is the one genome
#      reinstalls after a wipe, and because upstream's CI builds on a release
#      toolchain. A beta is a fallback, not a default.
#
# Nothing here touches `xcode-select`: which Xcode is globally selected is a
# machine-wide decision, and this build has no business making it.
licence_accepted() {
  DEVELOPER_DIR="$1" "$XCODEBUILD" -license check >/dev/null 2>&1
}

require_xcode() {
  [ -x "$XCODEBUILD" ] || die "$XCODEBUILD is missing"

  local candidates=()
  if [ -n "${ATU_DEVELOPER_DIR:-}" ]; then
    candidates=("$ATU_DEVELOPER_DIR")
  else
    for c in /Applications/Xcode.app /Applications/Xcode-beta.app; do
      [ -d "$c/Contents/Developer" ] && candidates+=("$c/Contents/Developer")
    done
  fi

  [ ${#candidates[@]} -gt 0 ] || die "no Xcode found in /Applications.

      AltTab is an .xcodeproj with a code-signing phase; the Command Line Tools
      alone cannot build it. genome installs Xcode through homebrew.masApps."

  for c in "${candidates[@]}"; do
    if licence_accepted "$c"; then
      DEVELOPER_DIR="$c"; export DEVELOPER_DIR
      case "$c" in
        */Xcode-beta.app/*)
          warn "building with a prerelease Xcode ($c).
        Upstream builds on a release toolchain, so if this fails in a way the
        patches cannot explain, accept the licence on /Applications/Xcode.app
        and try again." ;;
      esac
      return
    fi
  done

  die "an Xcode is installed but its licence has not been accepted.

      The licence is per-install, and plain \`sudo xcodebuild -license accept\`
      applies to whatever \`xcode-select -p\` points at ($(xcode-select -p 2>/dev/null || echo 'nothing')),
      which is not necessarily the one needed here. Name it explicitly:

        sudo env DEVELOPER_DIR=${candidates[0]} xcodebuild -license accept
        sudo env DEVELOPER_DIR=${candidates[0]} xcodebuild -runFirstLaunch"
}

installed_version() {
  [ -d "$APP" ] || return 1
  /usr/bin/defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null
}

receipt_field() {
  [ -f "$RECEIPT" ] || return 1
  jq -re ".$1" "$RECEIPT" 2>/dev/null
}
