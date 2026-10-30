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
$ shop -a imagemagick.out convert -version   # name the package yourself, remember nothing
$ shop -s rg@15.1.0 jq@1.8.1               # one shell, each from its own nixpkgs revision
```

Try it without installing anything:

```bash
nix run git+https://codeberg.org/weegs710/nix-shop#shop -- --help
```

## The Index

The version index ships inside this repo, so you don't build it. It is generated data and it keeps growing, so this page doesn't quote its size. `shop --rev` shows the revision a bare command resolves against, and `shop -l <command>` lists every version it knows. To build your own, see [The index](./docs/index.md).

## What It Is

Three projects each solve part of the problem. None of them solve all of it:

- **[nix-index](https://github.com/nix-community/nix-index)** knows _command → attribute_. `rg` is `ripgrep`.
- **[comma](https://github.com/nix-community/comma)** runs an attribute ephemerally, without installing it.
- **[nixpkgs-multiverse](https://github.com/fzakaria/nixpkgs-multiverse)** knows _attribute + version → revision_, lazily, across every revision nixpkgs ever published.

nix-shop merges concepts from all three and does what none of them do alone: **ephemerally run a package from any nixpkgs revision ever published**, with the name lookup and the build guaranteed to come from the same tree.

## What Can I Drop When I Adopt It?

nix-shop borrows ideas from three projects but needs only one of them at runtime.

| Project            | Keep it?                   | Why                                                                                                                                                                                                              |
| ------------------ | -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| comma              | **No**                     | shop never calls comma. It reimplements comma's lookup in `lib/shop.nu` and leaves out the `NIX_PATH` branch that sends comma to the wrong nixpkgs. Keep comma only if you use it on its own.                    |
| nixpkgs-multiverse | **No**                     | The engine is vendored in `lib/engine.nix`, and `restock` generates the index from NixOS's own release bucket and the nixpkgs git history. The flake takes no multiverse input.                                  |
| nix-index-database | **Yes**, or an equivalent  | shop asks `nix-locate` which package ships a command, and that needs a database. shop bundles the nix-index program but not a database. The prebuilt one is the easy source, and building your own also works.    |

So you can stop pinning comma and nixpkgs-multiverse on nix-shop's account. nix-shop's flake inputs are only `nixpkgs` and `nixpkgs-darwin`. It uses whichever `nix-locate` comes first on your `PATH`, and the revision it pairs with travels inside the index as `index/paired-rev`, so it needs no nix-index-database input of its own.

If you do use [nix-index-database](https://github.com/nix-community/nix-index-database)'s module, comma is opt-in there (`programs.nix-index-database.comma.enable`), so you can leave it off.

**With no database at all**, shop still does two things. `shop -a <package> <command>` never asks the database, so it works. A command whose name is also an attribute, like `cowsay`, resolves through the attribute fallback. Anything else, like `rg`, stops with `no executable 'rg' in the nix-index database`.

## How Is This Different From nix run?

`nix run` isn't tied to your nixpkgs. It runs from whatever ref you name, so `nix run github:NixOS/nixpkgs/nixos-25.11#ab-av1` and `nix run github:NixOS/nixpkgs/nixos-unstable#ab-av1` give you different versions. What you have to supply is the ref and the attribute name. shop works out both.

| You have                       | `nix run`                                                          | `shop`                                              |
| ------------------------------ | ------------------------------------------------------------------ | --------------------------------------------------- |
| a command, like `ffprobe`      | needs an attribute, and `ffprobe` isn't one. It ships inside `ffmpeg` | asks the nix-index database which package ships it |
| a version, like `jq` 1.5       | needs the channel, tag or commit that shipped it                   | finds the revision                                  |
| an unfree package              | refuses unless `NIXPKGS_ALLOW_UNFREE=1` and `--impure` are set     | evaluates with `allowUnfree`                        |

Command → attribute is nix-index's idea, not nix-shop's, and the credits below say so. What nix-shop adds is **version → revision**, plus keeping the name lookup and the build on the same tree.

**Documentation:** [Why this exists](./docs/why.md) ·
[Versions and pickers](./docs/versions.md) ·
[Unfree packages](./docs/unfree.md) ·
[The index](./docs/index.md) ·
[Platforms](./docs/platforms.md)

## Flags

shop's own flags go **before** the command:

```
-l, --list <cmd>      every version of that command, with its revision
-p, --print <cmd>     which packages provide that command
-s, --shell <cmd>...  open a shell with all of those on PATH instead of running one
-a, --attr <pkg>      name the package yourself, remembering nothing
    --pick            ask which package again, even if one is remembered
    --cache           see, forget, clear or set what shop remembers
    --rev             which revision a bare command resolves against
-h, --help            show this
```

Flags come first and combine, as in `shop -l -a imagemagick.out` or `shop -s --pick convert`. The first token that isn't one of them is the command, and everything after it is handed to the package untouched, so **there is no separator to remember** and shop's flags and the package's own can never collide. The exception is `-s`, which opens a shell instead of running anything, so every token after its flags is a package. `-a` takes the package after it, and `--cache` takes the rest of the line. Where a flag sits decides what it means:

```console
$ shop jq@1.5 --version
jq-1.5

$ shop -l rg                  # -l here is shop's --list
┌─────────┬─────────────────────────┐
│ version │        revision         │
├─────────┼─────────────────────────┤
│ 0.4.0   │ 17.03                   │
├─────────┼─────────────────────────┤
│ 0.6.0   │ 17.09                   │
...

$ shop rg -l hello .          # -l here is ripgrep's --files-with-matches
./a.txt
```

Coming from comma you may reach for a `--`. Don't. shop has nothing to consume it, so it lands on the program as a literal argument and breaks the call.

When several packages ship one command, shop asks which you meant, remembers the answer, and says on stderr which package it used. With no terminal to ask on it stops instead of guessing. [The choices cache](./docs/versions.md#the-choices-cache) covers `--cache`, `--pick`, `-a`, and what changed for scripts.

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

Fork it and do whatever. Bug fixes and improvements welcome.

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
