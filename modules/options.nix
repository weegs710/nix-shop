{ lib, ... }:
{
  options.programs.shop = {
    enable = lib.mkEnableOption "shop, for running any version of any package without installing it";

    index = lib.mkOption {
      type = lib.types.path;
      default = ../index;
      defaultText = lib.literalExpression "nix-shop's shipped index";
      description = "Index directory holding revisions.json and versions.json; build your own with restock";
    };

    pinned = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Revision a bare command resolves against; defaults to the index's own paired-rev";
    };

    clone = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/you/nixpkgs.git";
      description = "Bare nixpkgs clone restock checks revisions out of";
    };

    installRestock = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install restock alongside shop";
    };
  };
}
