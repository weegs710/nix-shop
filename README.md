# nix-shop

Run **any version of any package**, without installing it. The command is `shop`.

> **Important**: This is a hobbyist project and I'm learning as I go. If something is broken or stupid, that's why. It's all FOSS, so take the whole thing or steal bits of it.

> **Requirements**: Nix, and a nix-index database. If `nix-locate rg` prints something, you're set.

## Quickstart

```console
$ shop rg foo.txt          # newest ripgrep, run right now, installed nowhere
$ shop jq@1.5 --version    # the exact jq that shipped as 1.5
$ shop jq@                 # pick a version from a menu
$ shop -l rg               # every ripgrep, with the revision each one came from
$ shop -s node@14.17.0     # ephemeral shell with an ancient node in it
```

Try it without installing anything:

```bash
nix run git+https://codeberg.org/weegs710/nix-shop#shop -- --help
```

## Status

**292,770 package versions** across **31,096 attributes**, from **1,405 revisions**, 2015-09-30 to 2026-08-07.

Paired with nixpkgs [`148bab9c1c3c`](https://github.com/NixOS/nixpkgs/commit/148bab9c1c3c53136ecb44a6ea356a0ed5b39b06). The index ships inside this repo, so you build **neither** of the databases nix-shop uses.

## What It Is

Three projects each solve part of the problem. None of them solve all of it:

- **[nix-index](https://github.com/nix-community/nix-index)** knows _command → attribute_. `rg` is `ripgrep`.
- **[comma](https://github.com/nix-community/comma)** runs an attribute ephemerally, without installing it.
- **[nixpkgs-multiverse](https://github.com/fzakaria/nixpkgs-multiverse)** knows _attribute + version → revision_, lazily, across every revision nixpkgs ever published.

nix-shop merges concepts from all three and does what none of them do alone: **ephemerally run a package from any nixpkgs revision ever published**, with the name lookup and the build guaranteed to come from the same tree.

**Documentation:** [Why this exists](./docs/why.md) ·
[Versions and pickers](./docs/versions.md) ·
[Unfree packages](./docs/unfree.md) ·
[The index](./docs/index.md) ·
[Platforms](./docs/platforms.md)

## Flags

```
shop <command>[@<version>] [args...]

-l, --list <cmd>    every version of that command, with its revision
-p, --print <cmd>   which packages provide that command
-s, --shell <cmd>   open a shell with it instead of running it
    --rev           which revision a bare command resolves against
-h, --help          show this
```

Colors turn off when stderr isn't a terminal, and `NO_COLOR` is respected.

## Install

As a flake input:

```nix
{
  inputs.nix-shop.url = "git+https://codeberg.org/weegs710/nix-shop";

  outputs = { self, nixpkgs, nix-shop, ... }: {
    nixosConfigurations.yourhost = nixpkgs.lib.nixosSystem {
      modules = [ nix-shop.nixosModules.default ];
    };
  };
}
```

Or just grab the packages:

```nix
environment.systemPackages = [
  nix-shop.packages.x86_64-linux.shop
  nix-shop.packages.x86_64-linux.restock
];
```

### Options

```nix
programs.shop = {
  enable = true;
  index = ./my-shop-index;   # default: the index shipped in this repo
  pinned = "<40-char-rev>";  # default: whatever index/paired-rev says
  clone = "/home/you/nixpkgs.git";  # default: null, restock reads $SHOP_CLONE or --clone
  installRestock = true;     # default: true
};
```

`nixosModules.default` and `homeModules.default` take the same options.

### Other Outputs

```
packages.<system>.shop        packages.<system>.restock       packages.<system>.default
overlays.default              adds shop and restock to pkgs
nixosModules.default          homeModules.default
lib.mkShopEngine              the engine as a plain function, no module needed
formatter.<system>            nixfmt
```

`lib.mkShopEngine` gives you the revision machinery without shop at all. See [The index](./docs/index.md#the-engine).

## Contributing

Fork it and do whatever. Bugs and improvements welcome.

If you're touching the nushell, `nu-check` passing doesn't mean much. Interpolated strings treat `(` as a subexpression opener, and it only blows up at runtime. Run the actual thing.

## Credits

| Who                                                                                            | For                                                            |
| ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| [fzakaria](https://fzakaria.com/2026/08/09/nixpkgs-multiverse-every-version-that-ever-existed) | the blog post that kicked this whole thing off                 |
| [nix-index](https://github.com/nix-community/nix-index)                                        | the command → attribute database this is built on              |
| [comma](https://github.com/nix-community/comma)                                                | the ephemeral-run idea and the resolution loop I reimplemented |
| [nixpkgs-multiverse](https://github.com/fzakaria/nixpkgs-multiverse)                           | the lazy revision engine, vendored, and the index design       |

## License

MIT, please see [LICENSE](LICENSE).

The nushell driver, the Python index tooling and the Nix modules are original work, and every one of those files carries `SPDX-License-Identifier: MIT` with my copyright.

Two files are vendored from **nixpkgs-multiverse**, MIT, copyright Farid Zakaria: `lib/engine.nix` and `tools/extract-versions.nix`. Both carry an SPDX header naming him, and the full license text is in [LICENSES/](LICENSES/).

comma is reimplemented rather than copied, and nix-index is called off `PATH`, so no code from either ships here. For the record, nix-index is BSD-3-Clause and comma is MIT.

`index/revisions.json` and `index/versions.json` are generated metadata about nixpkgs -- revisions, dates, hashes and version strings. They contain no nixpkgs source.

## Links

- Codeberg: https://codeberg.org/weegs710/nix-shop
- Website: https://weegs.dev
