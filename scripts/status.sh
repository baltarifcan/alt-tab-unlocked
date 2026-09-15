#!/usr/bin/env bash
#
# What is pinned, what is installed, and whether they agree. Changes nothing.
# Exits 0 when in sync, 1 when not, so genome's `just drift` can gate on it.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

DRIFT=0

bold "alt-tab-unlocked"
info "pinned:    $(pin tag) ($(pin version)), commit $(pin commit | cut -c1-12)"

if ! live="$(installed_version)"; then
  warn "not installed at $APP"
  printf '\n  run: alt-tab-unlocked install\n'
  exit 1
fi
info "installed: $live at $APP"

if [ -f "$RECEIPT" ]; then
  info "built:     $(receipt_field builtAt) with $(receipt_field xcode)"
  info "signed:    $(receipt_field identity)"
else
  warn "no build receipt at $RECEIPT — this AltTab was not installed by this tool.
        It is most likely an upstream download, which means the Pro gate is back."
  DRIFT=1
fi

if [ "$live" != "$(pin version)" ]; then
  warn "installed $live but pinned $(pin version)"
  DRIFT=1
fi

if rc="$(receipt_field commit 2>/dev/null)" && [ "$rc" != "$(pin commit)" ]; then
  warn "receipt records commit ${rc:0:12}, pin says $(pin commit | cut -c1-12)"
  DRIFT=1
fi

# A patch edited after the install is the quiet failure: the source of truth in
# git no longer describes the app that is actually running.
if [ -f "$RECEIPT" ]; then
  while read -r name sha; do
    [ -z "$name" ] && continue
    live_sha="$(shasum -a 256 "$ATU_ROOT/patches/$name" 2>/dev/null | awk '{print $1}')"
    if [ -z "$live_sha" ]; then
      warn "patch $name was installed but no longer exists in this repo"; DRIFT=1
    elif [ "$live_sha" != "$sha" ]; then
      warn "patch $name changed since the install"; DRIFT=1
    fi
  done < <(jq -r '.patches[] | "\(.name) \(.sha256)"' "$RECEIPT" 2>/dev/null)
fi

# The check that decides whether any of this is still allowed.
printf '\n'
"$ATU_ROOT/scripts/verify-licence.sh" --offline || DRIFT=1

printf '\n'
if [ "$DRIFT" -eq 0 ]; then
  printf '\033[32mIn sync.\033[0m\n'
else
  printf '\033[33mOut of sync.\033[0m Run `alt-tab-unlocked install` to reconcile.\n'
fi
exit "$DRIFT"
