# nix/options.nix — options shared by the NixOS and Home Manager modules
{ lib, ... }:

let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.programs.inir = {
    enable = mkEnableOption "iNiR, the Quickshell desktop shell for Niri";

    package = mkOption {
      type = types.package;
      description = "iNiR package. The flake injects a default built with your own pkgs.";
    };

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.whisper-cpp pkgs.cloudflare-warp ]";
      description = "Extra packages put on inir.service's PATH (optional integrations: warp-cli, whisper-cpp, ...).";
    };

    installRuntimePackages = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Also install iNiR's runtime tools (kitty, nautilus, fuzzel, wl-clipboard,
        cliphist, grim, playerctl, ...) for the whole session, not only inside
        the inir wrapper. Needed for the default niri keybinds to work.
      '';
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = { INIR_LOG_LEVEL = "debug"; };
      description = "Extra environment variables for inir.service.";
    };

    fonts.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Install Material Symbols, JetBrainsMono Nerd Font, Roboto Flex, Gabarito, Oxanium, Readex Pro, Rubik, Space Grotesk, Twemoji, DejaVu, Liberation, Noto.";
    };

    dots.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Provide iNiR's default dotfiles (niri config wired to inir, kdeglobals,
        darklyrc, fuzzel, GTK 3/4 settings, Kvantum, kitty, foot). NixOS installs
        them as system-wide fallbacks under /etc and seeds writable files before
        Niri starts; Home Manager also seeds them on activation. Custom files
        are preserved. Exact legacy defaults are migrated with a backup.
      '';
    };

    mascot.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Use the package variant that bundles the optional Kira mascot art pack.";
    };

    polkitAgent.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Run polkit-gnome as a user service tied to niri.service.";
    };

    service = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Create the inir systemd user service.";
      };

      compositor = mkOption {
        type = types.nullOr (types.enum [ "niri" ]);
        default = "niri";
        description = "Which compositor unit auto-starts inir.service. null = create the unit without wiring.";
      };
    };
  };
}

