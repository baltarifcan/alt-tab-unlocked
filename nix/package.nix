{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  coreutils,
  curl,
  diffutils,
  findutils,
  git,
  gnugrep,
  gnused,
  jq,
  pin,
}:

# Packages the *builder*, not the app.
#
# There is no derivation here that produces AltTab.app, and that is not an
# oversight. The upstream project links SkyLight.framework out of
# /System/Library/PrivateFrameworks, embeds three local SwiftPM packages, and
# code-signs against the login keychain — none of which exist inside the Nix
# sandbox, and nixpkgs' xcbuild does not stand in for xcodebuild here. So Nix
# owns what is reproducible (the pinned commit, the patches, the tool and its
# dependencies) and the impure part stays visibly impure.

stdenvNoCC.mkDerivation {
  pname = "alt-tab-unlocked";
  version = pin.version;

  src = lib.cleanSourceWith {
    src = ../.;
    filter =
      path: type:
      let
        base = baseNameOf path;
      in
      base != ".git" && base != "result" && !lib.hasSuffix ".lock" base;
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    libexec=$out/libexec/alt-tab-unlocked
    mkdir -p "$libexec" $out/bin
    cp -r scripts patches licence pin.json "$libexec/"
    chmod +x "$libexec"/scripts/*.sh

    makeWrapper "$libexec/scripts/cli.sh" $out/bin/alt-tab-unlocked \
      --set ATU_ROOT "$libexec" \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          coreutils
          curl
          diffutils
          findutils
          git
          gnugrep
          gnused
          jq
        ]
      }

    runHook postInstall
  '';

  # Catches the obvious breakage — a syntax error in a script, a renamed
  # subcommand — at build time rather than on wipe day.
  doInstallCheck = true;
  installCheckPhase = ''
    for s in $out/libexec/alt-tab-unlocked/scripts/*.sh; do
      ${bash}/bin/bash -n "$s"
    done
    $out/bin/alt-tab-unlocked --help > /dev/null
  '';

  meta = {
    description = "Builds AltTab from pinned upstream source with the Pro gate patched out";
    homepage = "https://github.com/baltarifcan/alt-tab-unlocked";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.darwin;
    mainProgram = "alt-tab-unlocked";
  };
}
