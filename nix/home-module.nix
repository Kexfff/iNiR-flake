# nix/home-module.nix
# `osConfig` is provided by Home Manager when it runs as a NixOS module.
{ config, lib, pkgs, osConfig ? null, ... }:

let
  inherit (lib) mkIf mkDefault mkOption types optional optionals;
  cfg = config.programs.inir;
  pkg = cfg.package;

  runtimeDir = "${pkg}/share/quickshell/inir";
  dots = "${pkg}/share/inir/dots";

  sessionEnv = {
    INIR_SYSTEM_RUNTIME_DIR = runtimeDir;
    INIR_FALLBACK_SYSTEM_RUNTIME_DIR = runtimeDir;
    GSETTINGS_SCHEMA_DIR = pkg.gsettingsSchemaDir;
    INIR_VENV = "${pkg.pythonEnv}";
    ILLOGICAL_IMPULSE_VIRTUAL_ENV = "${pkg.pythonEnv}";
    QT_QPA_PLATFORMTHEME = "kde";
    XDG_MENU_PREFIX = "plasma-";
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    MOZ_ENABLE_WAYLAND = "1";
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
  } // lib.optionalAttrs pkg.hasDarkly { QT_STYLE_OVERRIDE = "Darkly"; };

  serviceEnv = sessionEnv // {
    QS_DISABLE_CRASH_HANDLER = "1";
    QT_SCALE_FACTOR = "1";
    QT_SCALE_FACTOR_ROUNDING_POLICY = "RoundPreferFloor";
    QT_LOGGING_RULES = "quickshell.dbus.properties=false;qt.qml.settings.warning=false;qt.core.qsettings.warning=false;kf.xmlgui=false;kf.coreaddons=false;kf.config.core=false;kf.iconthemes=false";
    # Do NOT clobber PATH like upstream does: keep every profile the user has.
    PATH = lib.concatStringsSep ":" ([
      (lib.makeBinPath ([ pkg ] ++ cfg.extraPackages))
      "%h/.nix-profile/bin"
      "/etc/profiles/per-user/%u/bin"
      "/run/wrappers/bin"
      "/run/current-system/sw/bin"
      "/usr/local/bin"
      "/usr/bin"
    ]);
  } // cfg.environment;

  toEnvList = lib.mapAttrsToList (n: v: "${n}=${v}");
in
{
  imports = [ ./options.nix ];

  options.programs.inir = {
    configSymlink.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Expose the packaged shell at ~/.config/quickshell/inir so `qs -c inir` and tools that expect the classic path work. Disable if you keep a git checkout there.";
    };
    dots.mode = mkOption {
      type = types.enum [ "copy" "symlink" ];
      default = "copy";
      description = "Seed writable runtime configuration. In symlink mode only Matugen templates are linked; runtime outputs and Niri configuration remain writable.";
    };
    pointerCursor.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Set home.pointerCursor to capitaine-cursors-light (24px) with GTK integration.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ pkg pkgs.xwayland-satellite ]
      ++ cfg.extraPackages
      ++ optionals cfg.installRuntimePackages pkg.sessionTools
      ++ optionals cfg.fonts.enable pkg.fonts;

    fonts.fontconfig.enable = mkIf cfg.fonts.enable true;

    home.sessionVariables = sessionEnv;
    systemd.user.sessionVariables = sessionEnv;   # visible to niri.service via environment.d

    xdg.enable = true;
    xdg.userDirs.enable = mkDefault true;

    xdg.configFile = lib.mkMerge [
      (mkIf cfg.configSymlink.enable { "quickshell/inir".source = runtimeDir; })
      (mkIf (cfg.dots.enable && cfg.dots.mode == "symlink") {
        "matugen".source = "${dots}/matugen";
      })
      (mkIf config.xdg.userDirs.enable {
        "autostart/xdg-user-dirs.desktop".text = "[Desktop Entry]\nType=Application\nName=User directories\nHidden=true\n";
      })
    ];

    home.activation.inirSeedDots = mkIf cfg.dots.enable
      (lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
        run ${pkg}/bin/inir-seed-config --target ${lib.escapeShellArg config.xdg.configHome}
      '');

    # Seed before Niri reads its configuration, including first login.
    systemd.user.services.inir-config = mkIf cfg.dots.enable {
      Unit = { Description = "Seed writable iNiR defaults"; Before = [ "niri.service" ]; };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkg}/bin/inir-seed-config --target \"${config.xdg.configHome}\"";
      };
      Install.WantedBy = [ "niri.service" ];
    };

    home.pointerCursor = mkIf cfg.pointerCursor.enable (mkDefault {
      package = pkgs.capitaine-cursors;
      name = "capitaine-cursors-light";
      size = 24;
      gtk.enable = true;
    });

    systemd.user.services.inir = mkIf cfg.service.enable {
      Unit = {
        Description = "iNiR shell";
        PartOf = [ "niri.service" ];
        Requisite = [ "niri.service" ];
        After = [ "niri.service" ];
        Before = [ "xdg-desktop-autostart.target" ];
        StartLimitIntervalSec = 30;
        StartLimitBurst = 3;
      };
      Service = {
        Type = "dbus";
        BusName = "org.kde.StatusNotifierWatcher";
        Environment = toEnvList serviceEnv;
        ExecStart = "${lib.getExe pkg} run --session";
        ExecStopPost = "-${lib.getExe pkg} cleanup-orphans";
        SuccessExitStatus = 143;
        KillMode = "process";
        KillSignal = "SIGTERM";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStopSec = 15;
        LimitCORE = 0;
        IOSchedulingPriority = 2;
      };
      Install.WantedBy = optional (cfg.service.compositor == "niri") "niri.service";
    };

    systemd.user.services.inir-polkit-agent = mkIf cfg.polkitAgent.enable {
      Unit = {
        Description = "PolicyKit authentication agent (polkit-gnome) for iNiR";
        PartOf = [ "graphical-session.target" ];
        After = [ "niri.service" ];
      };
      Service = {
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 1;
      };
      Install.WantedBy = [ "niri.service" ];
    };

    # Not possible from Home Manager alone — surface it loudly instead of failing silently.
    warnings = optional (osConfig == null || !(osConfig.programs.inir.enable or false)) ''
      programs.inir (Home Manager): make sure the system side provides
        security.pam.services.swaylock = {};   programs.ydotool.enable = true;
        hardware.i2c.enable = true;            xdg.portal (gtk + gnome portals)
      or simply import the NixOS module of this flake as well.
    '';
  };
}

