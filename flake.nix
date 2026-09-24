{
  description = "iNiR — complete desktop shell for Niri (Quickshell). Batteries-included NixOS + Home Manager flake.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Upstream shell source. Override it to track another branch or a fork:
    #   inputs.inir.inputs.inir-src.url = "github:snowarch/iNiR/prerelease";
    inir-src = {
      url = "github:snowarch/iNiR";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, inir-src, ... }:
    let
      inherit (nixpkgs) lib;
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      versionFile = "${inir-src}/VERSION";
      version =
        if builtins.pathExists versionFile
        then lib.removeSuffix "\n" (builtins.readFile versionFile)
        else "0-unstable-${inir-src.shortRev or "dirty"}";

      # Build against *any* nixpkgs so consumers get one Qt closure, not two.
      mkPackages = pkgs: rec {
        inir = pkgs.callPackage ./nix/package.nix {
          src = inir-src;
          inherit version;
        };
        inir-mascot-pack = pkgs.callPackage ./nix/mascot-pack.nix { };
        inir-with-mascot = inir.override { mascotSrc = inir-mascot-pack; };
        default = inir;
      };

      # The modules are plain Nix files. The flake only injects a default
      # package (built with the consumer's own pkgs), so
      #   programs.inir.enable = true;
      # is genuinely all a consumer has to write.
      withDefaultPackage = module: { config, pkgs, lib, ... }:
        let p = mkPackages pkgs; in {
          imports = [ module ];
          programs.inir.package = lib.mkDefault
            (if config.programs.inir.mascot.enable then p.inir-with-mascot else p.inir);
        };
    in
    {
      packages = forAllSystems mkPackages;

      overlays.default = final: _prev: removeAttrs (mkPackages final) [ "default" ];

      nixosModules = rec {
        inir = withDefaultPackage ./nix/nixos-module.nix;
        default = inir;
      };

      homeManagerModules = rec {
        inir = withDefaultPackage ./nix/home-module.nix;
        default = inir;
      };
      homeModules = self.homeManagerModules;

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.inir;
        };
      });

      checks = forAllSystems (pkgs: {
        package = self.packages.${pkgs.stdenv.hostPlatform.system}.inir;
        session-profile = pkgs.buildEnv {
          name = "inir-session-profile-check";
          paths = self.packages.${pkgs.stdenv.hostPlatform.system}.inir.sessionTools;
          pathsToLink = [ "/bin" "/share" ];
        };
        configuration = pkgs.runCommand "inir-configuration-check" {
          nativeBuildInputs = [ pkgs.python3 pkgs.niri pkgs.bash ];
          INIR_TEST_PACKAGE = self.packages.${pkgs.stdenv.hostPlatform.system}.inir;
        } ''
          export HOME="$TMPDIR/home"
          mkdir -p "$HOME"
          mkdir -p tests nix
          cp ${./tests}/*.py tests/
          cp ${./nix/seed-config.py} nix/seed-config.py
          python3 -m unittest discover -s tests
          ${self.packages.${pkgs.stdenv.hostPlatform.system}.inir}/bin/inir-seed-config
          niri validate -c "$HOME/.config/niri/config.kdl"
          GSETTINGS_SCHEMA_DIR="${self.packages.${pkgs.stdenv.hostPlatform.system}.inir.gsettingsSchemaDir}" \
            ${pkgs.glib}/bin/gsettings list-keys org.gnome.desktop.interface >/dev/null
          touch "$out"
        '';
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
