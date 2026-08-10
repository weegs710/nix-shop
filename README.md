# nix-shop - run any version of any package, without installing it

> **Important**: this is a hobbyist project. im learning as i go. if somethings broken or stupid, thats why. it works on my machine and my workflow. it might work on yours, it might not. no guarantees. its all FOSS, take the whole thing or steal bits of it, i dont care.

> **Requirements**: nushell. the driver and restock are written in nushell. theyre wrapped so you dont have to install it yourself -- nix pulls it in -- but if youre reading the source, thats what youre reading. `restock` additionally needs a bare nixpkgs clone, python3 and git, all wired for you.

the command is `shop`. the project is `nix-shop`.

```console
$ shop rg foo.txt          # newest ripgrep, run right now, installed nowhere
$ shop jq@1.5 --version    # the exact jq that shipped as 1.5, out of a 2018 revision
jq-1.5
$ shop jq@                 # searchable menu of every jq that ever existed
$ shop -l rg               # every ripgrep, with the revision each one came from
$ shop -s node@14.17.0     # ephemeral shell with an ancient node in it
```

try it without installing anything:

```bash
nix run git+https://codeberg.org/weegs710/nix-shop#shop -- --help
```

if that errors saying the attribute doesnt exist, add `--refresh` -- nix caches flake evaluations and will happily serve you a stale one.

## what it actually is

three projects each do a third of this, and none of them do it together:

- **[nix-index](https://github.com/nix-community/nix-index)** knows *command -> attribute*. `rg` is `ripgrep`. thats a database, not a guess.
- **[comma](https://github.com/nix-community/comma)** runs an attribute ephemerally, without installing it.
- **[nixpkgs-multiverse](https://github.com/fzakaria/nixpkgs-multiverse)** knows *attribute + version -> revision*, lazily, across every revision nixpkgs ever published.

shop takes the mechanism from all three and pairs the first with the last. thats the part none of them can do alone, and its the whole reason this exists.

## why

i was using comma and it kept failing to find things. packages id know were in nixpkgs, and comma would just shrug and id go `nix run` it instead.

turns out comma has a branch nobody talks about:

```rust
let use_channel = env::var("NIX_PATH").unwrap_or_default().contains("nixpkgs=");
...
if use_channel {
    run_cmd.args(["-f", "<nixpkgs>", choice]);   // nixpkgs_flake IGNORED
}
```

if `NIX_PATH` has `nixpkgs=` in it -- mine does, probably yours does -- comma throws away `COMMA_NIXPKGS_FLAKE` entirely and builds against `<nixpkgs>`. meanwhile it looked the *name* up in a database built from a completely different nixpkgs. two different trees. any package the database knows that your tree renamed or dropped comes back "no attribute" and you go `nix run` it, which is exactly what i was doing.

so the fix isnt "patch comma". the fix is to make the database and the resolver aim at the same tree by construction, and once you can do that, you might as well make the *version* a thing you can ask for too. `shop --rev` tells you which revision youre resolving against:

```console
$ shop --rev
2026-08-01-148bab9c1c3c (exact pairing with the nix-index database)
```

exact pairing means the revision recorded in nix-index-database's own lock is in shops index, so name lookup and build come from the same nixpkgs. thats the whole ballgame.

## features

<details>
<summary>the version axis</summary>

`shop -l <command>` lists every version nixpkgs ever shipped, with the revision each came from:

```console
$ shop -l jq
┌─────────┬─────────────────────────┐
│ version │        revision         │
├─────────┼─────────────────────────┤
│ 1.5     │ 2018-10-24-c70ad805d216 │
├─────────┼─────────────────────────┤
│ 1.6     │ 2023-09-25-6500b4580c2a │
├─────────┼─────────────────────────┤
│ 1.7     │ 2024-01-08-317484b1ead8 │
...
```

then `shop jq@1.5` runs that exact one. old builds still substitute out of cache.nixos.org -- ive pulled 2016-era binaries against glibc 2.25 with nothing compiling from source.

heads up: some packages version themselves stupidly. rpcs3 stamps its upstream git sha into the version string (`0.0.5-6980-81e5f3b7f`), so that column gets wide. thats nixpkgs data, not shop mangling it.

</details>

<details>
<summary>pickers</summary>

leave the version off after the `@` and you get a fuzzy-searchable menu of every version, newest first, with the revision beside it:

```console
$ shop jq@
every jq that ever existed
> 1.8.2    2026-07-19-241313f4e8e5
  1.8.1    2026-07-05-d407951447dc
  1.8.0    2025-07-08-9807714d6944
```

when several packages ship the same command, shop asks which one you meant and remembers the answer:

```console
$ shop -p convert
┌───────────────────────────────────────┐
│                 attr                  │
├───────────────────────────────────────┤
│ imagemagickBig.out                    │
├───────────────────────────────────────┤
│ imagemagick_light.out                 │
...
```

top-level attributes get offered first, because only those carry a version axis. comma will happily hand you `python314Packages.yt-dlp`; shop gives you `yt-dlp`.

your picks live in `~/.cache/shop/choices.json`. delete a key or the whole file to be asked again.

</details>

<details>
<summary>unfree packages</summary>

this one took a rewrite to get right.

the nix-index database is built from **file listings on the binary cache**. hydra doesnt build unfree packages, so theyre not on the cache, so theres no file listing, so they never enter the database at all. `nix-locate /bin/rpcs3` is empty. so is discord, steam, vscode, obsidian, spotify.

shops *version* index doesnt have that problem -- it comes from evaluating nixpkgs with `allowUnfree`, not from the cache. so shop knows every version of rpcs3 that ever existed, it just cant learn that the command `rpcs3` maps to the attribute `rpcs3`.

so when the database has nothing, shop falls back to trying the name as an attribute:

```console
$ shop -l rpcs3
no /bin/rpcs3 in the database -- resolving the attribute 'rpcs3' directly
┌────────────────────────┬─────────────────────────┐
│ 0.0.5-6980-81e5f3b7f   │ 2019-06-02-ae71c13a92f7 │
...
```

**caveat, and its a real one:** resolving is not running. unfree packages arent on the cache -- thats *why* they were missing -- so actually launching one means building it locally. for discord thats mostly an unpack. for rpcs3 thats a full C++ compile. shop will start it without complaining, so know what youre asking for.

</details>

<details>
<summary>the flags</summary>

```
shop <command>[@<version>] [args...]

-l, --list <cmd>    every version of that command, with its revision
-p, --print <cmd>   which packages provide that command
-s, --shell <cmd>   ephemeral shell with it, instead of running it
    --rev           which revision a bare command resolves against
-h, --help          the full help, with examples
```

colours turn off when you pipe it, and `NO_COLOR` is respected.

</details>

## the databases -- read this bit

there are **two** databases involved and they do different jobs. this trips people up, so:

| #   | database              | answers                    | who provides it        | do you build it? |
| --- | --------------------- | -------------------------- | ---------------------- | ---------------- |
| 0   | the nix-index database | "`rg` is the package `ripgrep`" | nix-community, prebuilt | no, and shop cant |
| 1   | shops version index    | "jq 1.5 lived in this revision" | ships inside nix-shop   | no, its included |

**neither one requires you to build anything.** install nix-shop and it works. the version index is committed right here in the repo -- 1405 revisions covering 2015 to now, 31,096 packages, 292,770 (package, version) pairs, 4.6MB. its a phone book, it contains no nixpkgs source. revisions get fetched lazily and only the ones you actually use ever land on your disk.

the nix-index one comes from wherever your system already gets it -- most people have it through [nix-index-database](https://github.com/nix-community/nix-index-database). if `nix-locate` works on your machine, youre set.

<details>
<summary>ok but what if i want my own version index</summary>

you only need this if you specifically want your own nixpkgs to be the newest thing shop knows about. if that sentence doesnt sound like something you want, **skip this whole section**, youre done.

still here? fair. reasons youd do it:

- youre on a different channel or pin than me and want shop resolving against yours
- you want the tip newer than whatever i last shipped
- you dont want to trust a database some guy on the internet built

**it takes about 30 minutes and needs about 3.2GB of disk.** heres the honest cost before you start:

| #   | what                        | cost                                    |
| --- | --------------------------- | --------------------------------------- |
| 0   | a bare nixpkgs clone         | ~3.2GB, one time, wont compress          |
| 1   | first full index build       | ~28 minutes on 12 threads, one time      |
| 2   | every update after that      | ~14 seconds                              |

```bash
git clone --bare https://github.com/NixOS/nixpkgs.git ~/nixpkgs.git
restock --clone ~/nixpkgs.git --index ./my-shop-index
```

then point shop at it:

```nix
programs.shop = {
  enable = true;
  index = ./my-shop-index;
};
```

after that, `restock` on its own is a 14 second incremental. run it whenever you want a newer tip. you do **not** need to run it every time you bump nixpkgs.

**keep the pairing.** an index also records which revision it's paired with, in `paired-rev`. if you dont tell restock what that is, you lose exact pairing and `shop --rev` will start saying "nearest indexed revision". point it at your nix-index database's lock:

```bash
restock --index ./my-shop-index --nix-index-lock /path/to/nix-index-database/flake.lock
# or straight up
restock --index ./my-shop-index --paired-rev <40-char-nixpkgs-rev>
```

</details>

<details>
<summary>which revision does a bare `shop rg` use</summary>

this is the whole reason shop exists, so its worth understanding.

when you type `shop rg`, two different things have to agree:

1. something has to know `rg` means `ripgrep` -- thats the nix-index database
2. something has to actually build `ripgrep` -- thats a nixpkgs revision

if those two come from **different** nixpkgs trees, you get comma's bug: the name database knows about a package your build tree renamed or dropped, and you get "no attribute" for something that obviously exists.

so shop resolves against the revision its index is *paired* with. ask it:

```console
$ shop --rev
2026-08-01-148bab9c1c3c (exact pairing with the nix-index database)
```

**exact pairing** means the two agree and youre golden. if it instead says **nearest indexed revision**, the two have drifted -- shop is falling back to the newest revision it knows, which still works, its just not guaranteed to match. thats a nudge to `restock`, not a fire.

</details>

<details>
<summary>how restock works</summary>

`restock` figures out which nixpkgs revision you're pinned to, then indexes forward to it. it reads the first of these it finds and tells you which one it used:

| #   | source                        | for                          |
| --- | ----------------------------- | ---------------------------- |
| 0   | `--pin <40-char-rev>`         | explicit                     |
| 1   | `--pin nixos-unstable`        | a channel, resolved live     |
| 2   | `flake.lock`                  | flakes, `follows` chains too |
| 3   | `.tack/pins.lock.json`        | [tack](https://github.com/manic-systems/tack) |
| 4   | `<nixpkgs>/.git-revision`     | channels                     |

use `--input <name>` if your nixpkgs input isnt called `nixpkgs`.

the revision list comes from the **`nix-releases` S3 bucket**, not from anywhere clever. a directory only appears there once hydra actually published that channel, which is precisely what makes its store paths substitutable. release points come from git tags in the clone.

indexing needs a bare nixpkgs clone -- about 3.2GB, and zstd wont compress it because packfiles are already compressed. each revision gets checked out into a scratch dir, hashed, and evaluated. the checkout never enters the nix store; materialising every revision into the store instead would want something like half a terabyte.

a full build is ~1400 revisions and took 28 minutes on 12 threads here. after that its incremental -- one new revision is about 14 seconds:

```console
$ restock
pin from tack pins.lock.json input 'nixpkgs'
1405 revisions (+1), 2015-09-30 .. 2026-08-07
indexing 1 revisions
index: 1 revisions merged, covering 1405/1405, 31,096 attrs, 292,770 pairs
```

you dont need to restock every time you bump nixpkgs. shops paired revision comes from **nix-index-database's** lock, not yours, so a bare `shop rg` keeps working. restock when you want a fresher tip, or when `--rev` stops saying "exact pairing".

</details>

<details>
<summary>the offset thing, if you go poking</summary>

`versions.json` stores **bare offsets** into `revisions.json`. so a restock that inserted a revision anywhere but the end would silently repoint every offset past it -- and the `revisionCount` guard wouldnt catch it, because the count still matches.

so restock only ever appends. anything new that sorts earlier than the current tail gets skipped loudly and told to `restock --rebuild` instead. that matters beyond offsets too: `at "<date>"` walks the array assuming date order, and `tip` is just the last element.

for what its worth, in 1383 channel bumps that condition has come up exactly once.

</details>

## platforms

| #   | system         | shop builds | resolves against |
| --- | -------------- | ----------- | ---------------- |
| 0   | x86_64-linux   | yes         | anything         |
| 1   | aarch64-linux  | yes         | anything         |
| 2   | aarch64-darwin | yes         | anything         |
| 3   | x86_64-darwin  | yes         | 26.05 and older  |

### intel macs

nixpkgs dropped `x86_64-darwin` after 26.05. most flakes just stopped shipping it. this one still does, because it takes a second input and thats a low price:

```nix
inputs.nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
```

and it barely matters which nixpkgs builds shop, because shops whole job is fetching *other* revisions at runtime. the nixpkgs it was built from only supplies nushell and nix-locate for the wrapper. verified: that branch carries `nushell-0.112.2` and `nix-index-0.1.10`, and every nushell feature shop leans on -- `def --wrapped`, `input list --fuzzy`, `is-terminal`, `ansi attr_dimmed`, `footer_mode` -- exists back there.

**but read this bit before you get excited.** the drop applies at *evaluation* time, so any nixpkgs revision newer than the cutoff throws when you evaluate it as `x86_64-darwin`. shop resolving a bare `shop rg` against a 2026-08 revision would blow up on first use. so on an Intel Mac, pin shop to the last revision that still had you:

```nix
programs.shop = {
  enable = true;
  pinned = "8c50a710ddca43d7a530fb805ad55bde8d0141c5";  # the 26.05 release
};
```

with that set, `shop rg` works, and `shop <pkg>@<version>` works for any version that existed at or before 26.05. versions that only ever appeared *after* the drop are genuinely out of reach -- theres no nixpkgs there to evaluate.

and the honest expiry: nixpkgs says 26.05 is the last release to carry `x86_64-darwin` at all. so this is a reprieve, not a cure.

<details>
<summary>the shipped index is built on x86_64-linux, and that matters a little</summary>

nixpkgs isnt identical across platforms -- some packages dont exist everywhere, and a handful carry different versions. the index i ship is extracted on x86_64-linux, so on another platform its slightly off. i measured it, on one revision, extracting the same tree as each system:

| #   | system         | attrs  | missing vs x86 | extra | different version |
| --- | -------------- | ------ | -------------- | ----- | ----------------- |
| 0   | x86_64-linux   | 24,827 | --             | --    | --                |
| 1   | aarch64-linux  | 24,779 | 48             | 0     | 6                 |
| 2   | aarch64-darwin | 24,770 | 59             | 2     | 93                |

so about 0.2% off on aarch64-linux and 0.6% on aarch64-darwin. shop still *builds* for your platform correctly -- the engine evaluates nixpkgs as your system, not mine. its only the version *listing* that came from mine. if that bothers you, build your own index on your own machine and itll be exact.

x86_64-darwin isnt in that table on purpose: a current nixpkgs revision cant be evaluated as x86_64-darwin at all, so theres nothing to compare. an Intel Mac uses my listing and pins to 26.05, per above.

</details>

## how it works

`lib/engine.nix` is a vendored copy of the nixpkgs-multiverse engine. i vendored it instead of pinning it for the same reason i vendored sprinkles in anomalos -- its ~200 lines of pure `builtins` and its load-bearing, so i want to own it outright rather than watch it bitrot. license and credit are in the file header.

three things i changed from upstream. it runs with `allowUnfree = true`, because upstreams stock outputs dont and unfree attributes just throw. it exposes a `versionTable` that returns version + revision in one evaluation, so `shop -l` doesnt do one eval per version. and it exposes a `knows` membership test, so checking whether an attribute exists doesnt mean building an entire version table to see if its empty.

the driver is nushell. `input list --fuzzy` is native there and renders tables with aligned columns, which is how the version picker shows you the revision while you filter -- piping flat lines into fzf could never do that, and it dropped a dependency. the index generators are python, because 1400 subprocess orchestrations and a 25-million-insertion merge is what pythons stdlib is for.

## getting started

as a flake input:

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

or just grab the packages:

```nix
environment.systemPackages = [
  nix-shop.packages.x86_64-linux.shop
  nix-shop.packages.x86_64-linux.restock
];
```

### options

```nix
programs.shop = {
  enable = true;
  index = ./my-shop-index;   # default: the index shipped in this repo
  pinned = "<40-char-rev>";  # default: whatever index/paired-rev says
  clone = "/home/you/nixpkgs.git";  # default: null, restock reads $SHOP_CLONE or --clone
  installRestock = true;     # default: true
};
```

both `nixosModules.default` and `homeModules.default` take the same options.

### the other outputs

```
packages.<system>.shop        packages.<system>.restock       packages.<system>.default
overlays.default              adds shop and restock to pkgs
nixosModules.default          homeModules.default
lib.mkShopEngine              the engine as a plain function, no module needed
formatter.<system>            nixfmt
```

`lib.mkShopEngine` is there if you want the revision machinery without shop at all -- hand it a `revisionsFile`, an `indexFile` and a `system` and you get `at`, `versions`, `latest`, `versionsOf`, `revOf` and `knows` to build whatever you want on top of.

or dont install it at all:

```bash
nix run git+https://codeberg.org/weegs710/nix-shop#shop -- jq@1.5 --version
```

## contributing

fork it and do whatever. bugs and improvements welcome. if youre touching the nushell, `nu-check` passing is necessary but nowhere near sufficient -- interpolated strings treat `(` as a subexpression opener and it only blows up at runtime. run the actual thing.

## credits

| #   | who                                                              | for                                                            |
| --- | ---------------------------------------------------------------- | -------------------------------------------------------------- |
| 0   | [nix-index](https://github.com/nix-community/nix-index)          | the command -> attribute database this is built on              |
| 1   | [comma](https://github.com/nix-community/comma)                  | the ephemeral-run idea and the resolution loop i reimplemented  |
| 2   | [nixpkgs-multiverse](https://github.com/fzakaria/nixpkgs-multiverse) | the lazy revision engine, vendored, and the index design       |
| 3   | [fzakaria](https://fzakaria.com/2026/08/09/nixpkgs-multiverse-every-version-that-ever-existed) | the blog post that kicked this whole thing off |

all three upstreams are MIT, and so is this.

## license

MIT. do whatever you want with it.

## links

- Codeberg: https://codeberg.org/weegs710/nix-shop
- Website: https://weegs.dev
