# alt-tab-unlocked

Builds [AltTab](https://github.com/lwouis/alt-tab-macos) from a pinned upstream
commit with the v11 Pro gate patched out, and installs the result.

This repository contains **no binaries and no upstream source**. It contains two
source patches, a build script, and a licence check that has to pass before
either of them runs.

```
alt-tab-unlocked install   # fetch the pinned tag, verify, patch, build, install
alt-tab-unlocked status    # what is pinned vs what is installed
alt-tab-unlocked verify    # re-run the licence check on its own
alt-tab-unlocked update    # bump the pin to the latest upstream release
```

---

## Modification notice

Required by GPLv3 §5(a), and worth stating plainly regardless:

> This is a **modified** version of alt-tab-macos. The modifications are the
> patches in `patches/`, first published 2026-09-15, against upstream
> `v11.6.1` (`850a7235`). They are distributed under the GNU General Public
> License v3, the same licence as the work they modify.
>
> This project is **not endorsed by, supported by, or affiliated with** Louis
> Pontoise or alt-tab.app. Do not report bugs in this build upstream — they
> are not his to fix. "AltTab" is upstream's name for upstream's product; no
> trademark licence is claimed or implied, and no built artifact is
> redistributed from here.

If you use AltTab and can afford it, [buy a Pro
licence](https://alt-tab.app/pricing). Upstream releasing this under the GPL is
the only reason this repository can exist.

## Why this is allowed

AltTab is GPLv3, and `src/pro/` — the entire licensing subsystem, gate,
keychain handling and upgrade-prompt scheduler — is in the public repository
under that licence. It is not a proprietary blob bolted onto free software.
That makes three clauses directly relevant:

- **§2** grants the right to run and privately modify without conditions. The
  personal-use half of this needs nothing else.
- **§5** grants the right to convey the modified source, provided the result
  stays GPLv3 and carries notice that it was changed and when. Hence the
  notice above, the per-file notices the patches insert, and `LICENCE.md`.
- **§3** is the one people expect to be a problem and is not. By conveying
  under GPLv3, upstream waived any power to forbid circumvention of a
  technological measure where the circumvention is effected by exercising GPL
  rights. That clause exists for precisely this case: shipping a licence check
  under the GPL and then reaching for anti-circumvention law to protect it.

What the GPL does **not** cover, and this repository therefore respects:

- **Trademark.** Copyright and trademark are separate grants, and §7(e) lets an
  author require removal of trade names from modified versions. Nothing here
  redistributes a built app or uses upstream's branding to identify this
  project.
- **Upstream's servers.** `RemoteLicenseClient` talks to a backend that is not
  GPL'd. The patch *deletes the check*; it does not forge a response, spoof a
  machine fingerprint, or plant a fabricated key in the keychain. Making your
  own copy return `.pro` is a §2 right. Sending fabricated credentials to
  someone else's server is a different question with no GPL defence, and this
  repository does not go there.

None of this is legal advice.

## The licence check

`lwouis` is the sole copyright holder, so he can release the next version under
any terms he likes. Rights already granted over `v11.6.1` are irrevocable and
permanent; they do not extend forward. So `scripts/verify-licence.sh` runs
automatically before every build and before every pin bump, and it **fails
closed**. It checks:

1. `LICENCE.md` at the pinned commit is byte-identical to canonical GPLv3,
   compared against the copy vendored in `licence/gpl-3.0.txt` — vendored so
   the check works offline and so an upstream edit cannot also move the
   reference.
2. Its sha256 matches `pin.json`, which the pinned (immutable) commit fixes.
3. No second licence-bearing file appeared at the repo root. GPLv3 §7
   additional terms can live in a `NOTICE` or `COPYING` without `LICENCE.md`
   changing at all.
4. GitHub still classifies the repository as GPL-3.0 — the earliest warning
   that `master` has moved off the licence.
5. The files the patches touch carry no per-file header contradicting it.

`scripts/fetch.sh` additionally refuses to build if the pinned tag has been
repointed to a different commit upstream.

## What the patches change

Two of them, both deliberately tiny so they survive upstream refactors and stay
reviewable.

**`0001-unlock-pro-features.patch`** — one function. `LicenseManager.computeState()`
returns `.pro`, and `state` initialises to `.pro`. Everything else keys off that
single value: `isProAvailable` / `isProLocked`, `ProFeature.attemptUse()`, the
`if case .pro { return nil }` early-exit in `ProTransitionScheduler`, and the
preference downgrade in `ProTransitionManager.onProLockEngaged()`. So one return
value unlocks the gated features (extra shortcuts, search in switcher, app
icons & titles style, auto-size, search-on-release) *and* suppresses the entire
Day 1 → Day 35 upgrade-prompt sequence, without touching any of the code that
implements them. The upstream implementation is kept in the file, renamed and
unused, so the next rebase is a diff and not an archaeology exercise.

It also means the app never contacts the licence API: `revalidateWithServer()`
guards on a keychain licence key that is never written.

**`0002-pin-sparkle-auto-update-off.patch`** — Sparkle's periodic check is
forced off. The appcast serves upstream's notarized build; left enabled it would
silently replace this locally-built app and restore the gate. The dropdown in
*Settings → General* still moves but no longer does anything. Updates come from
`alt-tab-unlocked update` instead. Note that a **manual** "check for updates"
click can still pull upstream's build over this one — that is a deliberate
action, so it is documented rather than blocked.

## Building

Needs a real Xcode, not just the Command Line Tools — the project is an
`.xcodeproj` that links `SkyLight.framework` from
`/System/Library/PrivateFrameworks`, embeds three local SwiftPM packages
(Sparkle, ShortcutRecorder, AppCenter, all vendored upstream so the build needs
no network for dependencies), and runs a code-signing phase.

One-time, if Xcode has never been run:

```sh
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

### Signing, and why you probably want a certificate

macOS binds TCC permissions — Accessibility and Screen Recording, both of which
AltTab is useless without — to the code signature. An ad-hoc signature has no
stable identity, so the system falls back to the cdhash, which changes on
**every rebuild**: you would re-grant Accessibility after every upgrade, and the
failure is silent (the app launches and lists no windows).

The build works ad-hoc out of the box, which is what makes an unattended
rebuild possible. Run this once to get a stable signature instead:

```sh
alt-tab-unlocked signing-cert
```

It generates a self-signed code-signing certificate, imports it into the login
keychain and trusts it for code signing. macOS will prompt for your password.

## Nix

```nix
{
  inputs.alt-tab-unlocked.url = "github:baltarifcan/alt-tab-unlocked";
}
```

`homeManagerModules.default` provides `programs.alt-tab-unlocked`:

```nix
programs.alt-tab-unlocked = {
  enable = true;
  # autoInstall = true;  # build during activation; off by default, see below
};
```

The flake packages **the builder**, not the app. There is no derivation that
produces `AltTab.app`: the sandbox has no `/System/Library/PrivateFrameworks`,
no login keychain and no `xcodebuild`, and nixpkgs' `xcbuild` does not stand in
for it on a project this shape. Nix owns what is genuinely reproducible — the
pinned commit, the patches, the tool and its dependencies — and the impure part
stays visibly impure rather than being dressed up as a derivation.

`autoInstall` is off by default. An `xcodebuild` is minutes of work needing the
network and a working Xcode, and home-manager activation is the wrong place to
find out one of those is missing, because a failure there fails the whole
switch. Left off, activation only reports drift and you run the install when you
mean to.

## Licence

GPLv3, same as upstream. See `LICENCE.md`.
