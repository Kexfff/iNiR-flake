# nix/deps.nix
#
# Every runtime dependency iNiR needs, mapped from the Arch package list
# (https://github.com/snowarch/iNiR/wiki/PACKAGES) onto nixpkgs attributes.
# Grouped exactly like the Arch meta-packages so it is easy to audit.
{ lib, pkgs }:

let
  # Attributes on nixos-unstable come and go. Never break evaluation because of
  # an optional helper — degrade gracefully instead (the shell handles absence).
  getOpt = path:
    let parts = lib.splitString "." path;
    in lib.optional (lib.hasAttrByPath parts pkgs) (lib.getAttrFromPath parts pkgs);
  firstOf = paths: lib.take 1 (lib.concatMap getOpt paths);

  # ---------------------------------------------------------------------------
  # Python: replaces the "managed venv" iNiR would otherwise try to create under
  # ~/.local/state/quickshell/.venv (materialyoucolor, InnerTube, yt-dlp with
  # SecretStorage, evdev, Pillow). Exposed as INIR_VENV / ILLOGICAL_IMPULSE_VIRTUAL_ENV.
  # ---------------------------------------------------------------------------
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    materialyoucolor
    pillow
    evdev
    ytmusicapi
    yt-dlp
    secretstorage
    requests
    psutil
    setproctitle
    numpy
    dbus-python
    pygobject3
    pycairo
  ]);

  # tesseract + tesseract-data-{eng,spa,rus,jpn,jpn_vert,chi_sim*,chi_tra*}
  tesseractWithLangs = pkgs.tesseract.override {
    enableLanguages = [
      "eng" "spa" "rus"
      "jpn" "jpn_vert"
      "chi_sim" "chi_sim_vert"
      "chi_tra" "chi_tra_vert"
    ];
  };

  # mpv + mpv-mpris
  mpvWithMpris = pkgs.mpv.override { scripts = [ pkgs.mpvScripts.mpris ]; };

  # ttf-roboto-flex, ttf-oxanium, ttf-gabarito-git, ttf-readex-pro,
  # ttf-rubik-vf, otf-space-grotesk  -> one google-fonts subset
  googleFonts = pkgs.google-fonts.override {
    fonts = [ "RobotoFlex" "Oxanium" "Gabarito" "ReadexPro" "Rubik" "SpaceGrotesk" ];
  };

  # darkly-bin (AUR) — Material You Qt widget style
  darkly = firstOf [ "darkly" "darkly-qt6" "kdePackages.darkly" ];

  # awww (wallpaper daemon) is a swww fork; fall back to swww if not packaged yet
  wallpaperDaemon = firstOf [ "awww" "swww" ];

  fonts = with pkgs; [
    material-symbols             # ttf-material-symbols-variable
    nerd-fonts.jetbrains-mono    # ttf-jetbrains-mono-nerd
    googleFonts
    dejavu_fonts                 # ttf-dejavu
    liberation_ttf               # ttf-liberation
    twemoji-color-font           # ttf-twemoji
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];

  # --------------------------- inir-core -------------------------------------
  core = (with pkgs; [
    bash coreutils findutils gnugrep gnused gawk procps util-linux
    bc curl wget ripgrep jq git rsync
    xdg-user-dirs xdg-utils
    wl-clipboard cliphist libnotify wlsunset
    polkit_gnome networkmanager gnome-keyring
    nautilus kitty foot fish gum
    xwayland-satellite glib dbus systemd
    kdePackages.kservice         # kbuildsycoca6 (called from the niri config)
  ]) ++ wallpaperDaemon;

  # ------------------------- inir-quickshell ---------------------------------
  qt6Modules = with pkgs.qt6; [
    qtbase qtdeclarative qtsvg qtwayland qt5compat qtimageformats qtmultimedia
    qtpositioning qtquicktimeline qtsensors qttools qttranslations qtvirtualkeyboard
  ];
  kdeModules = with pkgs.kdePackages; [
    kirigami kdialog syntax-highlighting breeze-icons plasma-integration
    kimageformats                # AVIF & friends (qt6-avif-image-plugin)
    qt6ct kconfig
    qtstyleplugin-kvantum        # kvantum
  ];
  quickshellStack = [ pkgs.quickshell pkgs.jemalloc ] ++ qt6Modules ++ kdeModules ++ darkly;

  # --------------------------- inir-audio ------------------------------------
  audio = (with pkgs; [
    pipewire wireplumber pulseaudio   # pactl
    playerctl pavucontrol
    kdePackages.plasma-browser-integration
    libdbusmenu-gtk3
    mpvWithMpris yt-dlp deno socat
    cava easyeffects lsp-plugins
  ]) ++ getOpt "yt-dlp-ejs";

  # ----------------------- inir-screencapture --------------------------------
  screencapture = with pkgs; [
    grim slurp swappy tesseractWithLangs wf-recorder imagemagick ffmpeg
  ];

  # -------------------------- inir-toolkit -----------------------------------
  toolkit = (with pkgs; [
    upower wtype ydotool brightnessctl ddcutil geoclue2
    swayidle swaylock blueman fprintd libqalculate hyprpicker
  ]) ++ getOpt "songrec" ++ getOpt "matugen";

  # --------------------------- inir-fonts ------------------------------------
  theming = with pkgs; [
    fontconfig fuzzel translate-shell
    adw-gtk3 capitaine-cursors mission-center uv
  ];

  # Directories the shell must be able to find via XDG_DATA_DIRS
  # (icons, GTK/GSettings schemas, cursors, fonts via <dir prefix="xdg">fonts</dir>).
  dataPackages = (with pkgs; [
    kdePackages.breeze-icons hicolor-icon-theme adwaita-icon-theme
    adw-gtk3 capitaine-cursors gsettings-desktop-schemas gtk3
    kdePackages.plasma-browser-integration
  ]) ++ fonts;

  # QML import roots + Qt plugin roots for the wrapper.
  # kirigami-wrapped ships no QML files; use the unwrapped output.
  kirigamiQml = pkgs.kdePackages.kirigami.unwrapped or pkgs.kdePackages.kirigami;
  qml = [ kirigamiQml ]
    ++ (with pkgs.kdePackages; [ syntax-highlighting kimageformats plasma-integration qtstyleplugin-kvantum breeze-icons ])
    ++ darkly
    ++ (with pkgs.qt6; [
      qtbase qt5compat qtdeclarative qtimageformats qtmultimedia qtpositioning
      qtquicktimeline qtsensors qtsvg qtvirtualkeyboard qtwayland
    ]);
in
{
  inherit pythonEnv fonts dataPackages qml;
  hasDarkly = darkly != [ ];

  # pythonEnv goes first so `python3` on the wrapper PATH is the closed env.
  runtime = lib.unique ([ pythonEnv ] ++ core ++ quickshellStack ++ audio ++ screencapture ++ toolkit ++ theming);

  # Handy for `environment.systemPackages` without the Qt library soup.
  sessionTools = lib.unique (core ++ audio ++ screencapture ++ toolkit ++ theming ++ [ pkgs.quickshell ] ++ darkly
    ++ (with pkgs.kdePackages; [ kdialog qt6ct qtstyleplugin-kvantum breeze-icons plasma-integration ]));
}

