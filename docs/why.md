# Why nix-shop exists

I'd been using comma and nix-index for a while, but comma would occasionally fail to find things -- packages I know are in nixpkgs. It would just shrug, and I'd go `nix run` it instead.

Digging into comma, I found the branch that explains it:

```rust
let use_channel = env::var("NIX_PATH")
    .unwrap_or_default()
    .contains("nixpkgs=");
...
if use_channel {
    run_cmd.args(["-f", "<nixpkgs>", choice]);
} else {
    run_cmd.args([format!("{nixpkgs_flake}#{choice}")]);
}
```

That same branch sits in both `run_command_or_open_shell` and `get_command_path`.

If `NIX_PATH` contains `nixpkgs=` -- mine does, and yours probably does -- comma throws away `COMMA_NIXPKGS_FLAKE` entirely and builds against `<nixpkgs>`. Meanwhile it looked the _name_ up in a database built from a different nixpkgs. **Two different trees.** Any package the database knows that your tree renamed or dropped comes back as "no attribute", and you go `nix run` it, which is exactly what I was doing.

Then someone posted [fzakaria's blog post](https://fzakaria.com/2026/08/09/nixpkgs-multiverse-every-version-that-ever-existed) on nixpkgs-multiverse and it clicked. The fix is making the database and the resolver aim at the **same tree by construction**. Once they're paired, the _version_ becomes something you can ask for too.

## Which Revision Does a Bare `shop rg` Use?

When you type `shop rg`, two things have to agree:

1. Something has to know `rg` means `ripgrep`. That's the nix-index database.
2. Something has to actually build `ripgrep`. That's a nixpkgs revision.

If those come from different nixpkgs trees you get the comma bug: the name database knows about a package your build tree renamed or dropped, and you get "no attribute" for something that obviously exists.

So shop resolves against the revision its index is _paired_ with.

## Checking the Pairing

```console
$ shop --rev
2026-08-01-148bab9c1c3c (exact pairing with the nix-index database)
```

**Exact pairing** means the revision recorded in nix-index-database's own lock is also in shop's index, so the name lookup and the build come from the same nixpkgs.

**Nearest indexed revision** means the two have drifted. shop falls back to the newest revision it knows, which still works, it's just not guaranteed to match. That's a nudge to run [`restock`](./index.md#restock), not a failure.
