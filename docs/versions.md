# Versions and Pickers

## The Version Axis

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

`shop jq@1.5` then runs that exact one. Old builds still substitute out of cache.nixos.org -- I've pulled 2016-era binaries against glibc 2.25 with nothing compiling from source.

Some packages version themselves strangely. rpcs3 stamps its upstream git sha into the version string (`0.0.5-6980-81e5f3b7f`), so that column gets wide. That's nixpkgs data, and shop prints it as-is.

## Pickers

Leave the version off after the `@` and you get a fuzzy-searchable menu of every version, newest first, with the revision beside it:

```console
$ shop jq@
every jq that ever existed
> 1.8.2    2026-07-19-241313f4e8e5
  1.8.1    2026-07-05-d407951447dc
  1.8.0    2025-07-08-9807714d6944
```

When several packages ship the same command, shop asks which one you meant and remembers the answer:

```console
$ shop convert
5 packages ship /bin/convert
>
──────────────────────────────────────────────
> imagemagick.out
  imagemagickBig.out
  imagemagick_light.out
  honeycomb-refinery.out
  graphicsmagick-imagemagick-compat.out
[1-5 of 5] [smart]
```

Top-level attributes are offered first, because only those carry a version axis. comma will hand you `python314Packages.yt-dlp`; shop gives you `yt-dlp`.

## The Choices Cache

Your picks live in `~/.cache/shop/choices.json`. Delete a key, or the whole file, to be asked again.

**One caveat.** If the first run wasn't a terminal -- inside a script, or with output piped -- shop takes the first candidate silently and caches that. `shop -p` is the only mode that reads and writes nothing.
