#!/usr/bin/env bash
#
# Move the pin to a newer upstream release. Refuses to move it to anything that
# is not still GPLv3, or that the patches do not cleanly apply to.
#
# This is the only place the pin is allowed to change, and it writes pin.json in
# the repo working tree — it does not commit. Review the diff, then commit.
#
# Usage: update-pin.sh [--tag vX.Y.Z] [--dry-run]

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TAG=""
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

OWNER="$(pin owner)"; NAME="$(pin repo)"

# $ATU_ROOT is the Nix store when installed through the flake, and the store is
# read-only. Bumping a pin is a repo edit, so it has to happen in a checkout.
[ -w "$PIN" ] || die "pin.json is not writable ($PIN).
      This looks like the Nix-store copy. Bump the pin from a git checkout:
        git clone https://github.com/baltarifcan/alt-tab-unlocked
        cd alt-tab-unlocked && ./scripts/update-pin.sh"

if [ -z "$TAG" ]; then
  bold "Looking up the latest upstream release"
  TAG="$(curl -fsSL "https://api.github.com/repos/${OWNER}/${NAME}/releases/latest" | jq -re .tag_name)" \
    || die "could not reach the GitHub API"
fi
info "candidate: $TAG"

if [ "$TAG" = "$(pin tag)" ]; then
  ok "already pinned to $TAG; nothing to do"
  exit 0
fi

# Resolve through a real checkout so the tag→commit mapping is verifiable rather
# than taken on the API's word.
mkdir -p "$CACHE"
if [ ! -d "$SRC/.git" ]; then git clone --quiet "$(pin upstream)" "$SRC"; else git -C "$SRC" fetch --quiet --tags origin; fi
COMMIT="$(git -C "$SRC" rev-list -n1 "$TAG" 2>/dev/null)" || die "tag $TAG not found upstream"
VERSION="${TAG#v}"
info "resolves to ${COMMIT:0:12}"

# Gate 1: is the new version still something we are allowed to modify?
printf '\n'
"$ATU_ROOT/scripts/verify-licence.sh" --ref "$COMMIT" \
  || die "refusing to bump the pin: $TAG is not verifiably GPLv3."

# Gate 2: do the patches still describe the new source?
printf '\n'
bold "Testing the patches against $TAG"
git -C "$SRC" reset --quiet --hard "$COMMIT"
git -C "$SRC" clean -qfdx --exclude=DerivedData
failed=0
for p in "$ATU_ROOT"/patches/*.patch; do
  if git -C "$SRC" apply --check "$p" 2>/dev/null; then
    ok "$(basename "$p") applies"
  else
    warn "$(basename "$p") does NOT apply to $TAG"
    failed=1
  fi
done
if [ "$failed" -eq 1 ]; then
  die "the patches need rebasing before the pin can move. In $SRC:
        git apply --3way <patch>   # resolve, then
        git diff > $ATU_ROOT/patches/<patch>"
fi

LICENCE_SHA="$(git -C "$SRC" show "${COMMIT}:$(pin licenceFile)" | shasum -a 256 | awk '{print $1}')"

if [ "$DRY" -eq 1 ]; then
  printf '\n\033[32mWould bump\033[0m %s -> %s\n' "$(pin tag)" "$TAG"
  exit 0
fi

jq --arg tag "$TAG" --arg commit "$COMMIT" --arg version "$VERSION" \
   --arg sha "$LICENCE_SHA" --arg at "$(date -u +%Y-%m-%d)" \
   '.tag=$tag | .commit=$commit | .version=$version | .licenceSha256=$sha | .pinnedAt=$at' \
   "$PIN" > "$PIN.new" && mv "$PIN.new" "$PIN"

printf '\n\033[32mPinned\033[0m %s (%s)\n' "$TAG" "${COMMIT:0:12}"
info "review and commit pin.json, then run: alt-tab-unlocked install"
