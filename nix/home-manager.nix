{ self, pin }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.alt-tab-unlocked;
  inherit (lib) mkEnableOption mkOption mkIf types;
in
{
  options.programs.alt-tab-unlocked = {
    enable = mkEnableOption "AltTab built from pinned upstream source with the Pro gate removed";

    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = "alt-tab-unlocked";
      description = "The builder CLI. The app itself is built by running it.";
    };

    applicationsDir = mkOption {
      type = types.str;
      default = "/Applications";
      description = ''
        Where the built app lands. /Applications is writable by the admin group
        on a default macOS install; use $HOME/Applications on a standard account.
      '';
    };

    autoInstall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Run the build during home-manager activation.

        Off by default, on purpose. An xcodebuild is several minutes of work that
        needs the network and a functioning Xcode, and activation is the wrong
        place to discover that any of those is missing — a failure there fails the
        whole switch. It also matches how this machine already treats Homebrew:
        a rebuild never silently upgrades anything.

        Left off, activation only reports when the installed app and the pin have
        drifted apart, and you run `alt-tab-unlocked install` when you mean to.
      '';
    };

    # Read-only, so `just drift` can ask the flake what it is supposed to see
    # in /Applications without parsing pin.json out of the store.
    version = mkOption {
      type = types.str;
      readOnly = true;
      default = pin.version;
      description = "Upstream version this configuration pins.";
    };
    tag = mkOption {
      type = types.str;
      readOnly = true;
      default = pin.tag;
      description = "Upstream release tag this configuration pins.";
    };
    commit = mkOption {
      type = types.str;
      readOnly = true;
      default = pin.commit;
      description = "Upstream commit this configuration pins.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    home.sessionVariables.ATU_APP_DIR = cfg.applicationsDir;

    home.activation.altTabUnlocked = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      if cfg.autoInstall then
        ''
          run ${cfg.package}/bin/alt-tab-unlocked install || \
            warnEcho "alt-tab-unlocked: install failed; run it by hand to see why"
        ''
      else
        ''
          # Never fails the switch. This is a report, not a build.
          if ! ${cfg.package}/bin/alt-tab-unlocked status > /dev/null 2>&1; then
            warnEcho "alt-tab-unlocked: AltTab is missing or not at ${cfg.tag}."
            warnEcho "                  run: alt-tab-unlocked install"
          fi
        ''
    );
  };
}
