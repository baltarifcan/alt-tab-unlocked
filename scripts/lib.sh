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

# Prefer the App Store Xcode, which is what genome reinstalls after a wipe.
# Xcode-beta is opt-in only: upstream CI builds on a release Xcode, and the
# project sets SWIFT_TREAT_WARNINGS_AS_ERRORS, so a beta toolchain is the most
# likely thing to break a build for reasons that have nothing to do with us.
resolve_developer_dir() {
  if [ -n "${ATU_DEVELOPER_DIR:-}" ]; then
    printf '%s' "$ATU_DEVELOPER_DIR"; return
  fi
  for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app; do
    [ -d "$candidate/Contents/Developer" ] && { printf '%s' "$candidate/Contents/Developer"; return; }
  done
  die "no Xcode found in /Applications. AltTab is an .xcodeproj with a code-signing
      phase; the Command Line Tools alone cannot build it. genome installs Xcode
      through homebrew.masApps."
}

require_xcode() {
  DEVELOPER_DIR="$(resolve_developer_dir)"
  export DEVELOPER_DIR
  [ -x "$XCODEBUILD" ] || die "$XCODEBUILD is missing"
  if ! "$XCODEBUILD" -license check >/dev/null 2>&1; then
    die "the Xcode licence has not been accepted yet. Run this once, it needs a password:

      sudo xcodebuild -license accept
      sudo xcodebuild -runFirstLaunch"
  fi
}

installed_version() {
  [ -d "$APP" ] || return 1
  /usr/bin/defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null
}

receipt_field() {
  [ -f "$RECEIPT" ] || return 1
  jq -re ".$1" "$RECEIPT" 2>/dev/null
}
