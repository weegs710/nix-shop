{
  lib,
  stdenv,
  runCommand,
  makeWrapper,
  writers,
  nix-index,
  shopIndex ? ./index,
  shopPinned ? null,
}:
let
  # The index carries which revision it is paired with, so shop needs no nix-index-database input to know it.
  pairedFile = shopIndex + "/paired-rev";
  pinned =
    if shopPinned != null then
      shopPinned
    else if builtins.pathExists pairedFile then
      lib.removeSuffix "\n" (builtins.readFile pairedFile)
    else
      null;

  engine = runCommand "shop-engine.nix" { } ''
    cat > $out <<EOF
    import ${./lib/engine.nix} {
      system = "${stdenv.hostPlatform.system}";
      revisionsFile = ${shopIndex}/revisions.json;
      indexFile = ${shopIndex}/versions.json;
      pinned = ${if pinned == null then "null" else ''"${pinned}"''};
    }
    EOF
  '';

  unwrapped = writers.writeNuBin "shop" (builtins.readFile ./lib/shop.nu);
in
# nix itself is left to PATH on purpose: shop must use the caller's nix, not a pinned one.
runCommand "shop"
  {
    nativeBuildInputs = [ makeWrapper ];
    meta = {
      description = "Run any version of any package, without installing it";
      mainProgram = "shop";
      license = lib.licenses.mit;
    };
  }
  ''
    makeWrapper ${unwrapped}/bin/shop $out/bin/shop \
      --set SHOP_ENGINE ${engine} \
      --suffix PATH : ${lib.makeBinPath [ nix-index ]}
  ''
