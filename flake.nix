{
  description = "iNiR - Home-manager module for snowarch's illogical-impulse on Niri (QuickShell)";

  inputs = {
    # These will be overridden by the user's flake
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Default upstream config - can be overridden by users
    inir = {
      url = "github:snowarch/iNiR";
      flake = false;
    };
  };

  outputs = inputs@{ self, nixpkgs, quickshell, inir, ... }:
    let
      flakeInputs = { inherit quickshell inir; };
    in {
      homeManagerModules.default = { config, lib, pkgs, ... }: (import ./home-module.nix) {
        inherit config lib pkgs;
        inputs = flakeInputs;
      };
      homeManagerModules.inir = self.homeManagerModules.default;
    };
}
