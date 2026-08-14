# Platforms

| System         | shop builds | Resolves against |
| -------------- | ----------- | ---------------- |
| x86_64-linux   | yes         | anything         |
| aarch64-linux  | yes         | anything         |
| aarch64-darwin | yes         | anything         |
| x86_64-darwin  | yes         | 26.05 and older  |

## Intel Macs

nixpkgs dropped `x86_64-darwin` after 26.05, and most flakes stopped shipping it. This one still does, because it costs one extra input:

```nix
inputs.nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
```

It barely matters which nixpkgs builds shop, because shop's whole job is fetching _other_ revisions at runtime. The nixpkgs it was built from only supplies nushell and nix-locate for the wrapper. That branch carries `nushell-0.112.2` and `nix-index-0.1.10`, and every nushell feature shop leans on -- `def --wrapped`, `input list --fuzzy`, `is-terminal`, `ansi attr_dimmed`, `footer_mode` -- exists back there.

**The drop applies at evaluation time.** Any nixpkgs revision newer than the cutoff throws when you evaluate it as `x86_64-darwin`, so a bare `shop rg` resolving against a 2026-08 revision would blow up on first use. On an Intel Mac, pin shop to the last revision that still carried your platform:

```nix
programs.shop = {
  enable = true;
  pinned = "8c50a710ddca43d7a530fb805ad55bde8d0141c5";  # the 26.05 release
};
```

With that set, `shop rg` works, and `shop <pkg>@<version>` works for any version that existed at or before 26.05. Versions that only appeared _after_ the drop are out of reach, because there's no nixpkgs there to evaluate.

This expires. nixpkgs says 26.05 is the last release carrying `x86_64-darwin` at all.

## The Shipped Index Is Built on x86_64-linux

nixpkgs isn't identical across platforms. Some packages don't exist everywhere, and a handful carry different versions. The index I ship is extracted on x86_64-linux, so on another platform it's slightly off. I measured it on one revision, extracting the same tree as each system:

| System         | Attrs  | Missing vs x86 | Extra | Different version |
| -------------- | ------ | -------------- | ----- | ----------------- |
| x86_64-linux   | 24,827 | --             | --    | --                |
| aarch64-linux  | 24,779 | 48             | 0     | 6                 |
| aarch64-darwin | 24,770 | 59             | 2     | 93                |

That's about **0.2% off** on aarch64-linux and **0.6%** on aarch64-darwin. shop still _builds_ for your platform correctly, because the engine evaluates nixpkgs as your system, not mine. Only the version _listing_ came from mine. Build your own index on your own machine and it'll be exact.

x86_64-darwin isn't in that table on purpose: a current nixpkgs revision can't be evaluated as x86_64-darwin at all, so there's nothing to compare. An Intel Mac uses my listing and pins to 26.05, per above.
