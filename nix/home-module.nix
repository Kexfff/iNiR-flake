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
      description = "copy: seed ~/.config once (editable, like the Arch installer). symlink: manage the files read-only via xdg.configFile.";
    };
    pointerCursor.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Set home.pointerCursor to capitaine-cursors-light (24px) with GTK integration.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ pkg ]
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
        "niri/config.kdl".source = mkDefault pkg.niriConfig;
        "kdeglobals".source = mkDefault "${dots}/kdeglobals";
        "darklyrc".source = mkDefault "${dots}/darklyrc";
        "fuzzel/fuzzel.ini".source = mkDefault "${dots}/fuzzel/fuzzel.ini";
        "gtk-3.0/settings.ini".source = mkDefault "${dots}/gtk-3.0/settings.ini";
        "gtk-4.0/settings.ini".source = mkDefault "${dots}/gtk-4.0/settings.ini";
        "Kvantum/kvantum.kvconfig".source = mkDefault "${dots}/Kvantum/kvantum.kvconfig";
        "kitty".source = mkDefault "${dots}/kitty";
        "foot/foot.ini".source = mkDefault "${dots}/foot/foot.ini";
      })
    ];

    # Copy-once seeding: never overwrites a file that already exists.
    home.activation.inirSeedDots = mkIf (cfg.dots.enable && cfg.dots.mode == "copy")
      (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        cfgdir="${config.xdg.configHome}"
        mkdir -p "$cfgdir/niri"
        if [ ! -e "$cfgdir/niri/config.kdl" ] && [ -f "${pkg.niriConfig}" ]; then
          run cp --no-preserve=mode,ownership "${pkg.niriConfig}" "$cfgdir/niri/config.kdl"
          echo "inir: seeded $cfgdir/niri/config.kdl"
        fi
        if [ -d "${dots}" ]; then
          run cp -r --update=none --no-preserve=mode,ownership "${dots}/." "$cfgdir/" || true
        fi
      '');

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

