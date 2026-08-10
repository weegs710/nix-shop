{
  callPackage,
  shopIndex ? ./index,
  shopPinned ? null,
  shopClone ? null,
}:
{
  shop = callPackage ./package.nix { inherit shopIndex shopPinned; };
  restock = callPackage ./restock.nix { inherit shopClone; };
}
