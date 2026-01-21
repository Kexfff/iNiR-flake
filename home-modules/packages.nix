inputs:

{ config, lib, pkgs, ... }:

let
  cfg = config.programs.inir;

  getPkg = path: lib.attrByPath path null pkgs;
  optPkg = path: let p = getPkg path; in lib.optional (p != null) p;

  customPkgs = import ../pkgs { inherit pkgs; };

  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.click
    ps.loguru
    ps.numpy
    ps.pillow
    ps.psutil
    ps.pycairo
    ps.pygobject3
    ps.tqdm
    ps."material-color-utilities"
    ps.materialyoucolor
    ps."kde-material-you-colors"
    ps.opencv4
  ]);

  optionalExtras =
    optPkg [ "cloudflare-warp" ] ++
    optPkg [ "blueman" ] ++
    optPkg [ "ollama" ] ++
    optPkg [ "mpvpaper" ] ++
    optPkg [ "cava" ] ++
    optPkg [ "easyeffects" ] ++
    optPkg [ "xwayland-satellite" ] ++
    optPkg [ "songrec" ];

  fontExtras =
    optPkg [ "rubik" ] ++
    optPkg [ "readex-pro" ] ++
    optPkg [ "space-grotesk" ] ++
    optPkg [ "twitter-color-emoji" ] ++
    optPkg [ "twemoji-color-font" ] ++
    optPkg [ "noto-fonts" ] ++
    optPkg [ "noto-fonts-cjk-sans" ] ++
    optPkg [ "noto-fonts-color-emoji" ] ++
    optPkg [ "nerd-fonts" "jetbrains-mono" ];

in {
  options.programs.inir.internal.pythonEnv = lib.mkOption {
    type = lib.types.package;
    internal = true;
    default = pythonEnv;
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      # Core
      niri
      bc
      coreutils
      cliphist
      curl
      wget
      ripgrep
      jq
      xdg-user-dirs
      rsync
      git
      wl-clipboard
      libnotify
      xdg-desktop-portal
      xdg-desktop-portal-gtk
      xdg-desktop-portal-gnome
      polkit
      networkmanager
      gnome-keyring
      dolphin
      foot
      gum

      # Quickshell runtime deps
      jemalloc
      libpipewire
      libxcb
      wayland
      libdrm
      mesa

      # Audio
      pipewire
      pipewire-pulse
      pipewire-alsa
      pipewire-jack
      wireplumber
      playerctl
      libdbusmenu-gtk3
      pavucontrol

      # Screenshots & recording
      grim
      slurp
      swappy
      tesseract
      wf-recorder
      imagemagick
      ffmpeg

      # Input toolkit
      upower
      wtype
      ydotool
      brightnessctl
      ddcutil
      geoclue2
      swayidle

      # Fonts & theming
      fontconfig
      dejavu_fonts
      liberation_ttf
      fuzzel
      glib
      translate-shell
      kvantum
      adw-gtk3
      capitaine-cursors
      hyprpicker

      # Icons & fonts
      customPkgs.material-symbols

      # Python runtime for scripts
      pythonEnv
    ]
    ++ optPkg [ "mate" "mate-polkit" ]
    ++ optPkg [ "mate-polkit" ]
    ++ optPkg [ "tesseract-data" ]
    ++ fontExtras
    ++ optionalExtras
    ++ optPkg [ "kdePackages" "breeze" ]
    ++ optPkg [ "kdePackages" "kde-gtk-config" ]
    ++ optPkg [ "kdePackages" "kdialog" ]
    ++ optPkg [ "kdePackages" "kirigami" ]
    ++ optPkg [ "kdePackages" "syntax-highlighting" ];
  };
}
