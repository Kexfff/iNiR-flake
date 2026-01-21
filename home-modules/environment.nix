inputs:

{ config, lib, ... }:

let
  cfg = config.programs.inir;

in {
  config = lib.mkIf cfg.enable {
    home.sessionVariables = {
      ILLOGICAL_IMPULSE_VIRTUAL_ENV = "${config.xdg.stateHome}/quickshell/.venv";
      qsConfig = "${config.xdg.configHome}/quickshell/ii";
      XDG_CURRENT_DESKTOP = "niri";
    };
  };
}
