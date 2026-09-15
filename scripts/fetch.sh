#!/usr/bin/env bash
#
# Put a clean checkout of the pinned upstream commit in $SRC, with the patches
# applied. Idempotent: re-running resets the tree, so a half-applied patch or a
# hand-edit never survives into a build.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

COMMIT="$(pin commit)"
TAG="$(pin tag)"
UPSTREAM="$(pin upstream)"

bold "Fetching ${UPSTREAM} @ ${TAG} (${COMMIT:0:12})"

mkdir -p "$CACHE"
if [ ! -d "$SRC/.git" ]; then
  rm -rf "$SRC"
  # A full clone rather than --depth 1: update-pin.sh needs to resolve tags
  # other than the pinned one, and the repo is small enough that the one-time
  # cost is not worth a second code path.
  git clone --quiet "$UPSTREAM" "$SRC"
  info "cloned into $SRC"
else
  git -C "$SRC" fetch --quiet --tags origin
  info "fetched into existing checkout"
fi

git -C "$SRC" cat-file -e "${COMMIT}^{commit}" 2>/dev/null \
  || die "pinned commit ${COMMIT} is not in the upstream repo. Was the tag moved or force-pushed?"

# The tag is a label and can be repointed; the commit hash cannot. Verify they
# still agree, and say so loudly if they do not, rather than silently building
# whatever the tag points at now.
tag_commit="$(git -C "$SRC" rev-list -n1 "$TAG" 2>/dev/null || true)"
if [ -n "$tag_commit" ] && [ "$tag_commit" != "$COMMIT" ]; then
  die "tag ${TAG} now points at ${tag_commit:0:12}, but pin.json pins ${COMMIT:0:12}.
      The tag was moved upstream. Investigate before building."
fi

git -C "$SRC" reset --quiet --hard "$COMMIT"
git -C "$SRC" clean -qfdx --exclude=DerivedData
ok "tree reset to ${COMMIT:0:12}"

"$ATU_ROOT/scripts/verify-licence.sh"

bold "Applying patches"
for p in "$ATU_ROOT"/patches/*.patch; do
  name="$(basename "$p")"
  git -C "$SRC" apply --check "$p" 2>/dev/null \
    || die "$name does not apply to ${TAG}.

      This is the expected failure mode when upstream refactors. Rebase the
      patch against the new source, do not force it:

        cd $SRC
        git apply --3way $p   # then fix the conflicts
        git diff > $ATU_ROOT/patches/$name"
  git -C "$SRC" apply "$p"
  ok "$name"
done

# GPLv3 §5(a): the conveyed modified work must carry prominent notices that it
# was changed, and when. The patches put a notice in each file they touch; this
# is the bundle-level one, and it is what `alt-tab-unlocked status` reads back
# out of the built app.
cat > "$SRC/ALT-TAB-UNLOCKED.md" <<NOTICE
This is a MODIFIED version of alt-tab-macos.

Upstream:  ${UPSTREAM}
Based on:  ${TAG} (${COMMIT})
Modified:  $(date -u +%Y-%m-%d) by the alt-tab-unlocked build
Changes:   $(cd "$ATU_ROOT/patches" && ls *.patch | tr '\n' ' ')

The modifications are distributed as source patches under the GNU General
Public License v3, the same licence as the work they modify. This build is
not endorsed by, supported by, or connected to Louis Pontoise. Do not report
bugs in this build upstream.
NOTICE
ok "wrote ALT-TAB-UNLOCKED.md (GPLv3 §5(a) change notice)"
