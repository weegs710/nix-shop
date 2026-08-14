# Unfree Packages

The nix-index database is built from **file listings on the binary cache**. Hydra doesn't build unfree packages, so they're not on the cache, so there's no file listing, so they never enter the database at all. `nix-locate /bin/rpcs3` is empty. So is discord, steam, vscode, obsidian and spotify.

shop's _version_ index doesn't have that problem. It comes from evaluating nixpkgs with `allowUnfree`, not from the cache, so shop knows every version of rpcs3 that ever existed. It just can't learn that the command `rpcs3` maps to the attribute `rpcs3`.

When the database has nothing, shop falls back to trying the name as an attribute:

```console
$ shop -l rpcs3
no /bin/rpcs3 in the database -- resolving the attribute 'rpcs3' directly
┌────────────────────────────┬─────────────────────────┐
│          version           │        revision         │
├────────────────────────────┼─────────────────────────┤
│ 0.0.5-6980-81e5f3b7f       │ 2019-06-02-ae71c13a92f7 │
├────────────────────────────┼─────────────────────────┤
│ 0.0.6-8187-790962425       │ 2020-03-27-ae6bdcc53584 │
├────────────────────────────┼─────────────────────────┤
│ 0.0.8-9300-341fdf7eb       │ 2020-12-09-e9158eca70ae │
...
```

**Resolving it isn't running it.** Unfree packages aren't on the cache, which is why they were missing in the first place, so launching one means building it locally. For discord that's mostly an unpack. For rpcs3 that's a full C++ compile, and shop will start it without warning you.
