# The Index

## Two Databases

There are two databases involved, and they do different jobs.

| Database               | Answers                         | Who provides it         | Do you build it?   |
| ---------------------- | ------------------------------- | ----------------------- | ------------------ |
| the nix-index database | "`rg` is the package `ripgrep`" | nix-community, prebuilt | no, and shop can't |
| shop's version index   | "jq 1.5 lived in this revision" | ships inside nix-shop   | no, it's included  |

**You build neither.** Install nix-shop and it works.

The version index is committed in this repo: **1,405 revisions** covering 2015-09-30 to 2026-08-07 (1,383 unstable bumps plus 22 release tags), **31,096 attributes**, **292,770 package versions**, 4.6MB. It's a phone book. It contains no nixpkgs source, and revisions are fetched lazily, so only the ones you actually use land on your disk.

The nix-index database comes from wherever your system already gets it, which for most people is [nix-index-database](https://github.com/nix-community/nix-index-database). If `nix-locate` works on your machine, you're set.

## Building Your Own

You only need this if you want your own nixpkgs to be the newest thing shop knows about. Reasons you'd do it:

- You're on a different channel or pin than me and want shop resolving against yours.
- You want the tip newer than whatever I last shipped.
- You don't want to trust a database some guy on the internet built.

The cost, before you start:

| What                    | Cost                                |
| ----------------------- | ----------------------------------- |
| a bare nixpkgs clone    | ~3.2GB, one time, won't compress    |
| first full index build  | ~28 minutes on 12 threads, one time |
| every update after that | ~14 seconds                         |

```bash
git clone --bare https://github.com/NixOS/nixpkgs.git ~/nixpkgs.git
restock --clone ~/nixpkgs.git --index ./my-shop-index
```

Then point shop at it:

```nix
programs.shop = {
  enable = true;
  index = ./my-shop-index;
};
```

**Keep the pairing.** An index records which revision it's paired with, in `paired-rev`. If you don't tell restock what that is, you lose exact pairing and `shop --rev` starts reporting "nearest indexed revision" instead. Point it at your nix-index database's lock:

```bash
restock --index ./my-shop-index --nix-index-lock /path/to/nix-index-database/flake.lock
# or directly
restock --index ./my-shop-index --paired-rev <40-char-nixpkgs-rev>
```

## restock

`restock` works out which nixpkgs revision you're pinned to, then indexes forward to it. It reads the first of these it finds, and tells you which one it used:

| Source                    | For                                           |
| ------------------------- | --------------------------------------------- |
| `--pin <40-char-rev>`     | explicit                                      |
| `--pin nixos-unstable`    | a channel, resolved live                      |
| `flake.lock`              | flakes, `follows` chains too                  |
| `.tack/pins.lock.json`    | [tack](https://github.com/manic-systems/tack) |
| `<nixpkgs>/.git-revision` | channels                                      |

Use `--input <name>` if your nixpkgs input isn't called `nixpkgs`.

The revision list comes from the **`nix-releases` S3 bucket**. A directory only shows up there once Hydra published that channel, which is what makes its store paths substitutable. Release points come from git tags in the clone.

Indexing needs a bare nixpkgs clone, about 3.2GB. Each revision is checked out into a scratch directory, hashed, and evaluated. The checkout never enters the nix store; materializing every revision into the store instead would want something like half a terabyte.

A full build is ~1,400 revisions and took me ~28 minutes across 12 threads. After that it's incremental, and one new revision is about **~14 seconds**:

```console
$ restock
pin from tack pins.lock.json input 'nixpkgs'
1405 revisions (+1), 2015-09-30 .. 2026-08-07
indexing 1 revisions
index: 1 revisions merged, covering 1405/1405, 31,096 attrs, 292,770 pairs
```

You don't need to restock every time you bump nixpkgs. shop's paired revision comes from **nix-index-database's** lock, not yours, so a bare `shop rg` keeps working. Restock when you want a fresher tip, or when `--rev` stops reporting exact pairing.

## Offsets, If You Go Poking

`versions.json` stores **bare offsets** into `revisions.json`. A restock that inserted a revision anywhere but the end would silently repoint every offset past it, and the `revisionCount` guard wouldn't catch it because the count still matches.

So restock only ever appends. Anything new that sorts earlier than the current tail is **skipped loudly**, pointing you at `restock --rebuild` instead. That matters beyond offsets too: `at "<date>"` walks the array assuming date order, and `tip` is just the last element.

In 1,383 channel bumps, that condition has come up exactly once.

## The Engine

`lib/engine.nix` is a vendored copy of the nixpkgs-multiverse engine. I vendored it rather than pinning it for the same reason I vendored _sprinkles_ in anomalos: it's ~180 lines of pure `builtins` and it's load-bearing, so I'd rather own it outright than watch it bitrot. `tools/extract-versions.nix`, which pulls the version of every attribute out of a checked-out revision, is vendored from the same place.

Both are Farid Zakaria's, MIT, with an SPDX header in each file and the full text in [LICENSES/](../LICENSES/).

Three things differ from upstream:

- It runs with `allowUnfree = true`, because upstream's stock outputs don't and unfree attributes throw.
- It exposes a `versionTable` returning version and revision in one evaluation, so `shop -l` doesn't do one eval per version.
- It exposes a `knows` membership test, so checking whether an attribute exists doesn't mean building a whole version table to see if it's empty.

`lib.mkShopEngine` is the engine as a plain function, usable without any module. Hand it a `revisionsFile`, an `indexFile` and a `system`, and you get:

| Group    | Attributes                                                |
| -------- | --------------------------------------------------------- |
| lookup   | `knows` `versionsOf` `versionTable` `revOf`               |
| packages | `at` `tip` `pkgs` `version` `versions` `latest`           |
| pinning  | `revisions` `revs` `releases` `pinnedLabel` `pinnedExact` |

## Why nushell and Python

The driver is nushell. `input list --fuzzy` is native there and renders tables with aligned columns, which is how the version picker shows you the revision while you filter. Piping flat lines into fzf could never do that, and going native drops me a dependency.

The index generators are Python, because 1,400 subprocess orchestrations and a 25-million-insertion merge is what Python's stdlib is for.
