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

When several packages ship the same command, shop asks which one you meant at a terminal and remembers the answer:

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

Your picks live in `~/.cache/shop/choices.json`, one package per command. Every run says which one it used, on stderr:

```console
$ shop convert -version
convert -> imagemagick.out (remembered)
WARNING: The convert command is deprecated in IMv7, use "magick" instead of "convert" or "magick convert"
...

$ shop rg --version
rg -> ripgrep.out (only candidate)
ripgrep 15.2.0
```

The note in brackets is `remembered`, `picked` (you chose just now), or `only candidate`. The attribute fallback for unfree packages prints its own line instead, and `-a` prints nothing because you named the package.

### Managing it

```console
$ shop --cache
~/.cache/shop/choices.json
┌───────────┬───────────────────┬────────────┐
│  command  │      package      │   picked   │
├───────────┼───────────────────┼────────────┤
│ convert   │ imagemagick.out   │ 2026-10-21 │
├───────────┼───────────────────┼────────────┤
│ pdftotext │ poppler-utils.out │ 2026-10-21 │
└───────────┴───────────────────┴────────────┘

$ shop --cache rm pdftotext
forgot 1, shop will ask again
┌───────────┬───────────────────┬────────────┐
│  command  │      package      │   picked   │
├───────────┼───────────────────┼────────────┤
│ pdftotext │ poppler-utils.out │ 2026-10-21 │
└───────────┴───────────────────┴────────────┘
```

| Command                              | Does                                                                                          |
| ------------------------------------ | --------------------------------------------------------------------------------------------- |
| `shop --cache`                       | list what is remembered, with the date each pick was made                                     |
| `shop --cache rm <cmd>...`           | forget those commands, and print what was forgotten                                           |
| `shop --cache clear`                 | forget everything, and print what was forgotten                                               |
| `shop --cache set <cmd> <attr.out>`  | remember a pick without a terminal; the package must be one that ships the command, as `shop -p` prints it |
| `shop --pick <cmd>`                  | ask again now, even if something is remembered; needs a terminal when several packages ship it |
| `shop -a <attr.out> <cmd> [args...]` | run `<cmd>` from the package you name; reads and writes nothing                                |

`-a` takes the package the way `shop -p` prints it. A name with no dot is a top-level attribute with its default output: `shop -a ripgrep rg --version`. A version works as it does for a command: `shop -a ripgrep.out@15.2.0 rg --version`. `-a` runs the command; `-l` and `-s` use what is remembered.

Entries made by older versions have no date and show `-`. They keep working, and older versions ignore the date on new ones.

### No terminal, no guess

**This is a breaking change.**

Before, when several packages shipped a command and shop had no terminal to ask on (a script, a pipe, a cron job, an agent), it took the first candidate and wrote it to the cache. That pick then stuck for every later run, and nothing said so. It now stops, exits 1, and lists the candidates:

```console
$ shop convert in.png out.jpg
shop: 5 packages ship /bin/convert, nothing is remembered for it, and there is no terminal to ask on
candidates:
  imagemagick.out
  imagemagickBig.out
  imagemagick_light.out
  honeycomb-refinery.out
  graphicsmagick-imagemagick-compat.out
name one and run it, remembering nothing:
  shop -a imagemagick.out convert [args...]
or remember one, then run the command again:
  shop --cache set convert imagemagick.out
or ask once from a real terminal:
  shop --pick convert
```

**What breaks:** a non-interactive call for a command that several packages ship, with nothing remembered for it. It used to succeed with whichever package sorted first. It now fails. A command with one candidate, one already remembered, or one that resolves as an unfree attribute behaves as before.

**What to do instead:** name the package with `shop -a <attr.out> <cmd>`, or remember it once with `shop --cache set <cmd> <attr.out>` and keep calling `shop <cmd>`. A script that wants the old behaviour has to pick the package itself, because shop no longer will.

**What else changed:** every run now prints one dimmed line on stderr saying which package it used. Stdout is untouched. The cache options are all flags, not a `cache` subcommand, so a command literally called `cache` (flutter ships one) is not shadowed.

`shop -p` still reads and writes nothing.
