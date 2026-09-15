{
  description = "AltTab, built from pinned upstream source with the v11 Pro gate patched out";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      pin = builtins.fromJSON (builtins.readFile ./pin.json);

      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forEach = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forEach (pkgs: rec {
        alt-tab-unlocked = pkgs.callPackage ./nix/package.nix { inherit pin; };
        default = alt-tab-unlocked;
      });

      apps = forEach (pkgs: rec {
        alt-tab-unlocked = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/alt-tab-unlocked";
        };
        default = alt-tab-unlocked;
      });

      # The app is installed per-user and signed against the login keychain, so
      # this is a home-manager module rather than a nix-darwin one. Nothing here
      # needs root.
      homeManagerModules.alt-tab-unlocked = import ./nix/home-manager.nix { inherit self pin; };
      homeManagerModules.default = self.homeManagerModules.alt-tab-unlocked;

      devShells = forEach (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = with pkgs; [
            jq
            git
            curl
            shellcheck
            nixfmt-rfc-style
          ];
          shellHook = ''export ATU_ROOT="$PWD"'';
        };
      });

      formatter = forEach (pkgs: pkgs.nixfmt-tree);
    };
}
