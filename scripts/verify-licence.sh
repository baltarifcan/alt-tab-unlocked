#!/usr/bin/env bash
#
# The permission check. Nothing in this repo builds or installs anything until
# this passes.
#
# What this repo does is legal because upstream is GPLv3 and stays GPLv3:
#
#   §2  grants the right to run and privately modify without conditions.
#   §5  grants the right to convey the modified source, which is what the
#       patches in patches/ are, provided the result stays GPLv3 and states
#       that it was changed and when. See README.md.
#   §3  is the one that matters for a licence check specifically: by conveying
#       under GPLv3, upstream waived any power to forbid circumvention of a
#       technological measure where that circumvention is effected by
#       exercising GPL rights. That is exactly patches/0001.
#
# Every one of those depends on the pinned commit actually being GPLv3. lwouis
# is the sole copyright holder, so he can ship the next version under different
# terms whenever he likes. Rights already granted over v11.6.1 are irrevocable,
# but they do not extend forward. So this runs on every build and on every pin
# bump, and it fails closed.
#
# Usage: verify-licence.sh [--ref <git-ref>] [--offline]
#   --ref      check a ref other than the pinned commit (used by update-pin.sh
#              before it is willing to move the pin)
#   --offline  skip the two checks that need github.com

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REF=""
OFFLINE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) REF="$2"; shift 2 ;;
    --offline) OFFLINE=1; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

OWNER="$(pin owner)"
NAME="$(pin repo)"
REF="${REF:-$(pin commit)}"
LICENCE_FILE="$(pin licenceFile)"
CANONICAL="$ATU_ROOT/licence/gpl-3.0.txt"

bold "Licence check — ${OWNER}/${NAME} @ ${REF}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

raw="https://raw.githubusercontent.com/${OWNER}/${NAME}/${REF}"
api="https://api.github.com/repos/${OWNER}/${NAME}"

# ---------------------------------------------------------------------------
# 1. The licence file at this exact ref is the unmodified GPLv3.
#
# Compared against the copy vendored in this repo, not against a fresh download
# from gnu.org: the check has to work offline and after a wipe, and a vendored
# reference is the only thing an upstream edit cannot also move.
# ---------------------------------------------------------------------------
if [ -f "$SRC/.git/config" ] && git -C "$SRC" cat-file -e "${REF}:${LICENCE_FILE}" 2>/dev/null; then
  git -C "$SRC" show "${REF}:${LICENCE_FILE}" > "$tmp/upstream.txt"
  info "read $LICENCE_FILE from the local checkout"
else
  [ "$OFFLINE" -eq 1 ] && die "no local checkout to read $LICENCE_FILE from, and --offline was given"
  curl -fsSL "${raw}/${LICENCE_FILE}" -o "$tmp/upstream.txt" \
    || die "could not fetch ${raw}/${LICENCE_FILE}"
  info "fetched $LICENCE_FILE from raw.githubusercontent.com"
fi

# Whitespace-insensitive: reflowing the text is not a licence change, and a
# stray CRLF should not read as one.
strip() { tr -d '[:space:]' < "$1"; }
if ! diff -q <(strip "$tmp/upstream.txt") <(strip "$CANONICAL") >/dev/null; then
  diff <(fold -w100 -s "$CANONICAL") <(fold -w100 -s "$tmp/upstream.txt") | head -40 >&2 || true
  die "${LICENCE_FILE} at ${REF} is NOT the unmodified GPLv3.

      Everything this repo does rests on that text. Stop here, read the diff
      above, and do not build or install until you understand what changed.
      If upstream has relicensed, the pinned commit is still yours under the
      terms it was released under, but you have no right to the new one."
fi
ok "${LICENCE_FILE} is byte-identical to canonical GPLv3 (modulo whitespace)"

# ---------------------------------------------------------------------------
# 2. It is the same file the pin was taken against.
# ---------------------------------------------------------------------------
want="$(pin licenceSha256)"
got="$(shasum -a 256 "$tmp/upstream.txt" | awk '{print $1}')"
if [ "$REF" = "$(pin commit)" ] && [ "$want" != "$got" ]; then
  die "${LICENCE_FILE} hash does not match pin.json.
      pinned:  $want
      actual:  $got
      The pinned commit is immutable, so this means the pin is inconsistent
      with the repo, or the fetch was tampered with."
fi
[ "$REF" = "$(pin commit)" ] && ok "sha256 matches pin.json"

# ---------------------------------------------------------------------------
# 3. No second licence file smuggling in extra terms.
#
# GPLv3 §7 lets an author attach additional terms. A rider in a NOTICE or
# COPYING file, or a "commercial use" EULA beside the GPL, would change what we
# are allowed to do without touching LICENCE.md at all.
# ---------------------------------------------------------------------------
if [ "$OFFLINE" -eq 0 ]; then
  if curl -fsSL "${api}/contents/?ref=${REF}" -o "$tmp/root.json" 2>/dev/null; then
    strays="$(jq -r '.[] | select(.type=="file") | .name' "$tmp/root.json" \
      | grep -iE '^(licen[cs]e|copying|notice|eula|terms|patents)' \
      | grep -vxF "$LICENCE_FILE" || true)"
    if [ -n "$strays" ]; then
      printf '%s\n' "$strays" | sed 's/^/      /' >&2
      die "unexpected licence-bearing file(s) at the repo root.
      GPLv3 §7 additional terms can live in any of these. Read them before
      building."
    fi
    ok "no additional licence files at the repo root"
  else
    warn "could not list the repo root (rate limit?); skipped the stray-licence check"
  fi

  # -------------------------------------------------------------------------
  # 4. GitHub still classifies the repo as GPL-3.0.
  #
  # Weaker than the checks above (GitHub reads the default branch, not our ref)
  # but it is the earliest warning that master has moved off the GPL, which is
  # the thing that would end this repo.
  # -------------------------------------------------------------------------
  if curl -fsSL "$api" -o "$tmp/repo.json" 2>/dev/null; then
    spdx="$(jq -r '.license.spdx_id // "none"' "$tmp/repo.json")"
    if [ "$spdx" != "GPL-3.0" ]; then
      die "GitHub now reports the licence of ${OWNER}/${NAME} as '${spdx}'.
      The pinned commit is unaffected — rights granted under GPLv3 cannot be
      revoked — but do not bump the pin past the relicensing commit."
    fi
    ok "GitHub still reports GPL-3.0 on the default branch"
  else
    warn "could not query the GitHub API (rate limit?); skipped the SPDX check"
  fi
else
  info "offline: skipped the stray-licence and SPDX checks"
fi

# ---------------------------------------------------------------------------
# 5. The files we patch carry no per-file header contradicting the repo licence.
# ---------------------------------------------------------------------------
targets="$(grep -hoE '^\+\+\+ b/\S+' "$ATU_ROOT"/patches/*.patch | sed 's|^+++ b/||' | sort -u)"
conflicts=0
while read -r f; do
  [ -z "$f" ] && continue
  if [ -f "$SRC/$f" ]; then head -20 "$SRC/$f" > "$tmp/head.txt"
  elif [ "$OFFLINE" -eq 0 ]; then curl -fsSL "${raw}/${f}" 2>/dev/null | head -20 > "$tmp/head.txt" || continue
  else continue
  fi
  if grep -qiE 'all rights reserved|proprietary|commercial licen[cs]e|not licen[cs]ed under' "$tmp/head.txt"; then
    warn "$f carries a header that may contradict the repo licence:"
    grep -inE 'all rights reserved|proprietary|commercial licen[cs]e|not licen[cs]ed under' "$tmp/head.txt" | sed 's/^/        /' >&2
    conflicts=1
  fi
done <<< "$targets"
[ "$conflicts" -eq 1 ] && die "read the headers above before building."
ok "no conflicting per-file licence headers on the patched files"

printf '\n\033[32mCleared.\033[0m %s/%s @ %s is GPLv3. §2, §3 and §5 apply.\n' "$OWNER" "$NAME" "${REF:0:12}"
