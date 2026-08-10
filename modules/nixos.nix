{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.programs.shop;
  packages = pkgs.callPackage ../packages.nix {
    shopIndex = cfg.index;
    shopPinned = cfg.pinned;
    shopClone = cfg.clone;
  };
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    programs.nix-index.enable = lib.mkDefault true;

    environment.systemPackages = [
      packages.shop
    ]
    ++ lib.optional cfg.installRestock packages.restock;
  };
}
