#!/usr/bin/env bash
# Remove what this tool put on the machine. Leaves AltTab's own preferences and
# its TCC grants alone: reinstalling should not cost you your settings.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

/usr/bin/pgrep -qx AltTab && { /usr/bin/osascript -e 'tell application "AltTab" to quit' >/dev/null 2>&1 || true; sleep 1; }

if [ -d "$APP" ]; then
  if [ -f "$RECEIPT" ]; then
    rm -rf "$APP"; ok "removed $APP"
  else
    warn "$APP has no build receipt, so it was not installed by this tool. Left alone."
  fi
fi
[ -f "$RECEIPT" ] && { rm -f "$RECEIPT"; ok "removed $RECEIPT"; }
[ -d "$CACHE" ]   && { rm -rf "$CACHE"; ok "removed $CACHE"; }

info "AltTab's preferences (com.lwouis.alt-tab-macos) and Privacy & Security"
info "grants were left in place. Remove them by hand if you want a clean slate."
