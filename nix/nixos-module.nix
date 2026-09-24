# nix/nixos-module.nix
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkIf mkDefault mkMerge mkOption types optional optionals mapAttrs;
  cfg = config.programs.inir;
  pkg = cfg.package;

  runtimeDir = "${pkg}/share/quickshell/inir";
  niriPkgs = optional config.programs.niri.enable config.programs.niri.package;

  # Everything the Arch installer would have put in the session environment.
  sessionEnv = {
    INIR_SYSTEM_RUNTIME_DIR = runtimeDir;
    INIR_FALLBACK_SYSTEM_RUNTIME_DIR = runtimeDir;
    GSETTINGS_SCHEMA_DIR = pkg.gsettingsSchemaDir;
    INIR_VENV = "${pkg.pythonEnv}";
    ILLOGICAL_IMPULSE_VIRTUAL_ENV = "${pkg.pythonEnv}";
    XDG_MENU_PREFIX = "plasma-";
    XCURSOR_THEME = "capitaine-cursors-light";
    XCURSOR_SIZE = "24";
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    MOZ_ENABLE_WAYLAND = "1";
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
  } // lib.optionalAttrs pkg.hasDarkly { QT_STYLE_OVERRIDE = "Darkly"; };

  serviceEnv = sessionEnv // {
    QT_QPA_PLATFORMTHEME = "kde";
    QS_DISABLE_CRASH_HANDLER = "1";
    QT_SCALE_FACTOR = "1";
    QT_SCALE_FACTOR_ROUNDING_POLICY = "RoundPreferFloor";
    QT_LOGGING_RULES = "quickshell.dbus.properties=false;qt.qml.settings.warning=false;qt.core.qsettings.warning=false;kf.xmlgui=false;kf.coreaddons=false;kf.config.core=false;kf.iconthemes=false";
  } // cfg.environment;

  # Existence is checked against the *source* (a flake input), never the built
  # package, so this does not trigger import-from-derivation.
  srcHas = rel: builtins.pathExists "${pkg.src}/${rel}";
  etcDefault = target: source: rel:
    lib.optionalAttrs (srcHas rel) { ${target}.source = mkDefault source; };
  dots = "${pkg}/share/inir/dots";
in
{
  imports = [ ./options.nix ];

  options.programs.inir = {
    users = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "alice" ];
      description = "Users added to the input/video/i2c/ydotool/networkmanager groups (ydotool typing, ddcutil brightness, evdev).";
    };
    niri.enable = mkOption { type = types.bool; default = true; description = "Enable programs.niri (nixpkgs module)."; };
    audio.enable = mkOption { type = types.bool; default = true; description = "PipeWire + WirePlumber + PulseAudio/ALSA compat + rtkit."; };
    network.enable = mkOption { type = types.bool; default = true; description = "NetworkManager (shell Wi-Fi panel)."; };
    bluetooth.enable = mkOption { type = types.bool; default = true; description = "Bluetooth + blueman."; };
    fingerprint.enable = mkOption { type = types.bool; default = false; description = "fprintd for the lock screen."; };
    greeter.enable = mkOption {
      type = types.bool;
      default = false;
      description = "greetd + tuigreet launching niri-session. Turn on if you have no display manager.";
    };
    ai.ollama.enable = mkOption { type = types.bool; default = false; description = "Local Ollama for the sidebar AI chat."; };
  };

  config = mkIf cfg.enable (mkMerge [
    # ------------------------------------------------------------- packages
    {
      warnings = optional (cfg.users == [ ]) "programs.inir.users is empty: set it to your login users to enable lock-before-sleep and hardware permissions.";
      environment.systemPackages =
        [ pkg pkgs.xwayland-satellite pkgs.xdg-desktop-portal-gtk pkgs.xdg-desktop-portal-gnome ]
        ++ cfg.extraPackages
        ++ optionals cfg.installRuntimePackages pkg.sessionTools;

      environment.sessionVariables = mapAttrs (_: mkDefault) sessionEnv;
      environment.etc = mkIf cfg.dots.enable (mkMerge [
        (etcDefault "niri" "${dots}/niri" "defaults/niri/config.kdl")
        (etcDefault "xdg/kdeglobals" "${dots}/kdeglobals" "dots/.config/kdeglobals")
        (etcDefault "xdg/darklyrc" "${dots}/darklyrc" "dots/.config/darklyrc")
        (etcDefault "xdg/fuzzel/fuzzel.ini" "${dots}/fuzzel/fuzzel.ini" "dots/.config/fuzzel/fuzzel.ini")
        (etcDefault "xdg/gtk-3.0/settings.ini" "${dots}/gtk-3.0/settings.ini" "dots/.config/gtk-3.0/settings.ini")
        (etcDefault "xdg/gtk-4.0/settings.ini" "${dots}/gtk-4.0/settings.ini" "dots/.config/gtk-4.0/settings.ini")
        (etcDefault "xdg/Kvantum/kvantum.kvconfig" "${dots}/Kvantum/kvantum.kvconfig" "dots/.config/Kvantum/kvantum.kvconfig")
        (etcDefault "xdg/foot/foot.ini" "${dots}/foot/foot.ini" "dots/.config/foot/foot.ini")
      ]);

      fonts = mkIf cfg.fonts.enable {
        packages = pkg.fonts;
        fontconfig = {
          enable = true;
          defaultFonts = {
            sansSerif = mkDefault [ "Roboto Flex" "Noto Sans" ];
            serif = mkDefault [ "Noto Serif" ];
            monospace = mkDefault [ "JetBrainsMono Nerd Font" ];
            emoji = mkDefault [ "Twitter Color Emoji" "Noto Color Emoji" ];
          };
        };
      };
    }

    # ---------------------------------------------------- compositor & session
    {
      programs.niri.enable = mkDefault cfg.niri.enable;
      programs.fish.enable = true;        # iNiR scripts are fish
      programs.dconf.enable = true;
      programs.ydotool.enable = true;     # ydotoold + uinput rules + group
      programs.xwayland.enable = mkDefault true;

      qt = {
        enable = true;
        platformTheme = mkDefault "kde";  # plasma-integration reads kdeglobals
      };

      hardware.graphics.enable = true;
      hardware.i2c.enable = true;         # ddcutil (external monitor brightness)

      services.dbus.enable = true;
      services.gvfs.enable = true;        # nautilus trash / mtp / smb
      services.udisks2.enable = true;
      services.upower.enable = true;
      services.geoclue2.enable = true;    # weather / night light location
      services.power-profiles-daemon.enable = mkDefault (!config.services.tlp.enable);
      services.gnome.gnome-keyring.enable = true;

      security.polkit.enable = true;
      security.rtkit.enable = mkIf cfg.audio.enable true;
      security.pam.services.login.enableGnomeKeyring = true;
      # Without this the swaylock fallback (and suspend-lock path) can never unlock.
      security.pam.services.swaylock = { };

      xdg.portal = {
        enable = true;
        xdgOpenUsePortal = mkDefault true;
        extraPortals = [ pkgs.xdg-desktop-portal-gtk pkgs.xdg-desktop-portal-gnome ];
        config.niri = mkDefault {
          default = [ "gnome" "gtk" ];
          "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
          "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
        };
      };
      xdg.mime.enable = true;
      xdg.icons.enable = true;

      services.pipewire = mkIf cfg.audio.enable {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
        wireplumber.enable = true;
      };

      networking.networkmanager.enable = mkIf cfg.network.enable true;

      hardware.bluetooth.enable = mkIf cfg.bluetooth.enable (mkDefault true);
      services.blueman.enable = mkIf cfg.bluetooth.enable true;

      services.fprintd.enable = mkIf cfg.fingerprint.enable true;
      services.ollama.enable = mkIf cfg.ai.ollama.enable true;

      users.groups = {
        input.members = cfg.users;
        video.members = cfg.users;
        i2c.members = cfg.users;
        ${config.programs.ydotool.group}.members = cfg.users;
      } // lib.optionalAttrs cfg.network.enable { networkmanager.members = cfg.users; };
    }

    # ---------------------------------------------------------------- greeter
    (mkIf cfg.greeter.enable {
      services.greetd = {
        enable = true;
        settings.default_session = {
          command = "${lib.getExe (pkgs.tuigreet or pkgs.greetd.tuigreet)} --time --remember --asterisks --cmd niri-session";
          user = "greeter";
        };
      };
      security.pam.services.greetd.enableGnomeKeyring = true;
    })

    # ---------------------------------------------------------- user services
    {
      systemd.user.services.inir = mkIf cfg.service.enable {
        description = "iNiR shell";
        wantedBy = optional (cfg.service.compositor == "niri") "niri.service";
        partOf = [ "niri.service" ];
        after = [ "niri.service" ];
        before = [ "xdg-desktop-autostart.target" ];
        # Full session PATH: system profile, per-user (Home Manager) profile,
        # setuid wrappers (pkexec/sudo) and the compositor client binary.
        path = [ pkg ] ++ niriPkgs ++ cfg.extraPackages
          ++ [ "/run/wrappers" "/etc/profiles/per-user/%u" "/run/current-system/sw" ];
        environment = serviceEnv;
        unitConfig = {
          Requisite = "niri.service";
          StartLimitIntervalSec = 30;
          StartLimitBurst = 3;
        };
        serviceConfig = {
          Type = "dbus";
          BusName = "org.kde.StatusNotifierWatcher";
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
      };

      systemd.user.services.inir-polkit-agent = mkIf cfg.polkitAgent.enable {
        description = "PolicyKit authentication agent (polkit-gnome) for iNiR";
        wantedBy = [ "niri.service" ];
        after = [ "niri.service" ];
        partOf = [ "graphical-session.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
          Restart = "on-failure";
          RestartSec = 1;
          TimeoutStopSec = 10;
        };
      };

      systemd.user.services.inir-config = mkIf cfg.dots.enable {
        description = "Seed writable iNiR defaults";
        wantedBy = [ "niri.service" ];
        before = [ "niri.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkg}/bin/inir-seed-config";
        };
      };

      # A user manager has no sleep.target. One system unit per configured user
      # runs as that user, and is inactive after each invocation so every sleep locks.
      systemd.services = lib.listToAttrs (map (user: {
        name = "inir-lock-before-sleep-${user}";
        value = {
          description = "Lock ${user}'s active iNiR session before sleep";
          wantedBy = [ "sleep.target" ];
          before = [ "sleep.target" ];
          path = [ pkgs.coreutils pkgs.systemd ];
          serviceConfig = {
            Type = "oneshot";
            User = user;
            TimeoutStartSec = 20;
          };
          script = ''
            export XDG_RUNTIME_DIR="/run/user/$(id -u)"
            export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
            systemctl --user is-active --quiet inir.service || exit 0
            ${lib.getExe pkg} lock prepareSleep
          '';
        };
      }) cfg.users);
    }
  ]);
}
