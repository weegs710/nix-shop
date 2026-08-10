{
  description = "Run any version of any package, without installing it";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # nixpkgs dropped x86_64-darwin after 26.05, so Intel Macs need the branch that still carries it.
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-darwin,
    }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      pkgsFor =
        system:
        if system == "x86_64-darwin" then
          nixpkgs-darwin.legacyPackages.${system}
        else
          nixpkgs.legacyPackages.${system};

      forAllSystems = f: lib.genAttrs systems (system: f (pkgsFor system));
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          inherit (pkgs.callPackage ./packages.nix { }) shop restock;
        in
        {
          inherit shop restock;
          default = shop;
        }
      );

      overlays.default = final: _prev: {
        inherit (self.packages.${final.stdenv.hostPlatform.system}) shop restock;
      };

      nixosModules.default = ./modules/nixos.nix;
      homeModules.default = ./modules/home-manager.nix;

      # The engine is a plain function, so anything can import it without going through a module.
      lib.mkShopEngine = import ./lib/engine.nix;

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
