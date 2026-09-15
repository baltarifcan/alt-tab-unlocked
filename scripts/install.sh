#!/usr/bin/env bash
#
# Build, then swap the result into /Applications and leave a receipt behind so
# `status` and genome's `just drift` can tell this app apart from a downloaded one.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

"$ATU_ROOT/scripts/build.sh"
BUILT="$(cat "$CACHE/last-build-path")"

bold "Installing to ${APP_DIR}"

[ -w "$APP_DIR" ] || die "$APP_DIR is not writable by $(id -un).
      On a default macOS install /Applications is writable by the admin group;
      if this account is not an admin, set ATU_APP_DIR=\$HOME/Applications."

was_running=0
if /usr/bin/pgrep -qx AltTab; then
  was_running=1
  /usr/bin/osascript -e 'tell application "AltTab" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do /usr/bin/pgrep -qx AltTab || break; sleep 0.25; done
  /usr/bin/pkill -x AltTab 2>/dev/null || true
  info "quit the running AltTab"
fi

# Replace rather than merge. A stale file from an older version left inside the
# bundle is the kind of thing that produces an unreproducible crash months later.
if [ -d "$APP" ]; then
  rm -rf "$APP.alt-tab-unlocked-old"
  mv "$APP" "$APP.alt-tab-unlocked-old"
fi
if cp -R "$BUILT" "$APP"; then
  rm -rf "$APP.alt-tab-unlocked-old"
else
  [ -d "$APP.alt-tab-unlocked-old" ] && mv "$APP.alt-tab-unlocked-old" "$APP"
  die "could not copy the app into $APP_DIR; the previous version was put back"
fi
ok "installed $APP"

mkdir -p "$STATE"
jq -n \
  --arg version   "$(pin version)" \
  --arg tag       "$(pin tag)" \
  --arg commit    "$(pin commit)" \
  --arg upstream  "$(pin upstream)" \
  --arg identity  "$("$ATU_ROOT/scripts/signing-identity.sh" --resolve)" \
  --arg builtAt   "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg xcode     "$("$XCODEBUILD" -version 2>/dev/null | head -1)" \
  --argjson patches "$(cd "$ATU_ROOT/patches" && for p in *.patch; do
      printf '{"name":"%s","sha256":"%s"}\n' "$p" "$(shasum -a 256 "$p" | awk '{print $1}')"
    done | jq -s .)" \
  '{version:$version, tag:$tag, commit:$commit, upstream:$upstream,
    identity:$identity, builtAt:$builtAt, xcode:$xcode, patches:$patches}' \
  > "$RECEIPT"
ok "wrote $RECEIPT"

"$ATU_ROOT/scripts/signing-identity.sh" --status

# TCC is SIP-protected: nothing can grant Accessibility on your behalf, and an
# app without it launches fine and then lists no windows, which reads as a bug
# rather than a missing permission.
bold "One thing left, by hand"
info "Grant Accessibility (and Screen Recording, for window previews) to the new"
info "AltTab. macOS cannot be scripted into this."
info "  System Settings > Privacy & Security > Accessibility"
info "If AltTab is already listed, toggle it off and on: the entry is bound to the"
info "old signature and will not carry over on its own."

if [ "$was_running" -eq 1 ]; then
  open -a "$APP" && info "relaunched AltTab"
fi
