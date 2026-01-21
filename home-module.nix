{ config, lib, pkgs, inputs, ... }:

let
  inherit (lib) mkEnableOption mkOption types;
  cfg = config.programs.inir;

in {
  imports = [
    (import ./home-modules/packages.nix inputs)
    (import ./home-modules/qt.nix inputs)
    (import ./home-modules/environment.nix inputs)
    (import ./home-modules/dotfiles.nix inputs)
  ];

  options.programs.inir = {
    enable = mkEnableOption "Enable the iNiR (illogical-impulse on Niri) QuickShell configuration";

    internal = {
      pythonEnv = mkOption {
        type = types.package;
        internal = true;
        description = "Python environment for iNiR scripts (internal use only)";
      };
    };
  };

  config = lib.mkIf cfg.enable { };
}
