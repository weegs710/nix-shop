# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 weegs710

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
