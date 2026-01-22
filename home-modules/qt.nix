inputs:

{ config, lib, pkgs, ... }:

let
  cfg = config.programs.inir;
  pythonEnv = cfg.internal.pythonEnv;

  qsPackage = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;

  maybeIcon = name: lib.optional (lib.attrByPath [ name ] null pkgs != null) (lib.attrByPath [ name ] null pkgs);

  qtImports = [
    pkgs.kdePackages.qtbase
    pkgs.kdePackages.qtdeclarative
    pkgs.kdePackages.qtsvg
    pkgs.kdePackages.qtwayland
    pkgs.kdePackages.qt5compat
    pkgs.kdePackages.qtimageformats
    pkgs.kdePackages.qtmultimedia
    pkgs.kdePackages.qtpositioning
    pkgs.kdePackages.qtquicktimeline
    pkgs.kdePackages.qtsensors
    pkgs.kdePackages.qttools
    pkgs.kdePackages.qttranslations
    pkgs.kdePackages.qtvirtualkeyboard
    pkgs.kdePackages.qtwebsockets
    pkgs.kdePackages.syntax-highlighting
    pkgs.kdePackages.kirigami.unwrapped
  ];

  customPkgs = import ../pkgs { inherit pkgs; };

  iconPkgs = [
    pkgs.adwaita-icon-theme
    pkgs.hicolor-icon-theme
    pkgs.papirus-icon-theme
    pkgs.kdePackages.breeze-icons
  ]
  ++ maybeIcon "colloid-icon-theme"
  ++ maybeIcon "moka-icon-theme"
  ;

in {
  config = lib.mkIf cfg.enable {
    home.packages = [
      (pkgs.writeShellScriptBin "qs" ''
        export QT_PLUGIN_PATH="${lib.makeSearchPath "lib/qt-6/plugins" qtImports}:${lib.makeSearchPath "lib/qt6/plugins" qtImports}:${lib.makeSearchPath "lib/plugins" qtImports}"
        export QML2_IMPORT_PATH="${lib.makeSearchPath "lib/qt-6/qml" qtImports}"
        export XDG_DATA_DIRS="${lib.makeSearchPath "share" (iconPkgs ++ [ customPkgs.material-symbols ])}:$HOME/.nix-profile/share:$HOME/.local/share:/etc/profiles/per-user/$USER/share:/run/current-system/sw/share:/usr/share:$XDG_DATA_DIRS"
        exec ${qsPackage}/bin/qs "$@"
      '')
      pkgs.matugen
    ] ++ iconPkgs ++ qtImports ++ [
      pkgs.qt6Packages.qt6ct
      pythonEnv
    ];
  };
}
