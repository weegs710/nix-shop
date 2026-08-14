# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 weegs710

{
  lib,
  runCommand,
  makeWrapper,
  writers,
  nushell,
  python3,
  git,
  nix-index,
  shopClone ? null,
}:
let
  tools = runCommand "shop-tools" { } ''
    mkdir -p $out
    cp ${./tools/revisions.nu} $out/revisions.nu
    cp ${./tools/index.py} $out/index.py
    cp ${./tools/extract-versions.nix} $out/extract-versions.nix
  '';

  unwrapped = writers.writeNuBin "restock" (builtins.readFile ./tools/restock.nu);

  # A bundled nix-locate must never shadow the caller's own, which is the only one carrying a database.
  wrapperArgs = [
    "--set SHOP_TOOLS ${tools}"
    "--suffix PATH : ${
      lib.makeBinPath [
        nushell
        python3
        git
        nix-index
      ]
    }"
  ]
  ++ lib.optional (shopClone != null) "--set SHOP_CLONE ${shopClone}";
in
runCommand "restock"
  {
    nativeBuildInputs = [ makeWrapper ];
    meta = {
      description = "Build and refresh a shop index against your own nixpkgs pin";
      mainProgram = "restock";
      license = lib.licenses.mit;
    };
  }
  ''
    makeWrapper ${unwrapped}/bin/restock $out/bin/restock ${lib.concatStringsSep " " wrapperArgs}
  ''
