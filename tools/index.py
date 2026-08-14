# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 weegs710

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent import futures
from pathlib import Path

HERE = Path(__file__).resolve().parent
EXTRACTOR = HERE / "extract-versions.nix"


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, check=False, **kw)


def binary_attrs():
    r = run(["nix-locate", "--minimal", "--at-root", "--regex", "/bin/[^/]+$"])
    if r.returncode != 0:
        sys.exit(f"nix-locate failed: {r.stderr.strip()}")
    names = set()
    for line in r.stdout.splitlines():
        attr = line.rsplit(".", 1)[0]
        if attr and "." not in attr:
            names.add(attr)
    return sorted(names)


def extract_one(clone, rev, attrs_expr, cache, ehash, tmpdir, need_hash):
    dest = cache / f"{rev}.{ehash}.json"
    if dest.exists() and not need_hash:
        return rev, None, "cached"

    tmp = tempfile.mkdtemp(dir=tmpdir)
    try:
        # Streaming git archive into tar keeps one copy of the tree on disk rather than a tarball beside it.
        git = subprocess.Popen(
            ["git", "-C", clone, "archive", "--format=tar", rev],
            stdout=subprocess.PIPE,
        )
        tar = subprocess.run(["tar", "-x", "-C", tmp], stdin=git.stdout, check=False)
        git.stdout.close()
        if git.wait() != 0 or tar.returncode != 0:
            return rev, None, "checkout failed"

        h = run(["nix", "hash", "path", "--sri", "--type", "sha256", tmp])
        narhash = h.stdout.strip() if h.returncode == 0 else None

        # A cached extraction with no narHash is unreachable at eval time, so the checkout is worth it for the hash alone.
        if dest.exists():
            return rev, narhash, "cached"

        e = run(
            [
                "nix-instantiate",
                "--eval",
                "--strict",
                "--json",
                "--arg",
                "revPath",
                tmp,
                "--arg",
                "attrs",
                attrs_expr,
                str(EXTRACTOR),
            ]
        )
        if e.returncode != 0:
            first = next((l for l in e.stderr.splitlines() if "error:" in l), "")
            return rev, narhash, f"eval failed: {first[:60]}"

        dest.write_text(e.stdout)
        return rev, narhash, None
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clone", required=True)
    ap.add_argument("--revisions", default="lib/shop/index/revisions.json")
    ap.add_argument("--out", default="lib/shop/index/versions.json")
    ap.add_argument("--cache", default="lib/shop/index/.per-rev")
    ap.add_argument("--tmpdir", default=None)
    ap.add_argument("--threads", type=int, default=12)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--incremental", action="store_true")
    ap.add_argument("--bin-attrs", action="store_true")
    ap.add_argument("--merge-only", action="store_true")
    args = ap.parse_args()

    revfile = Path(args.revisions)
    out = Path(args.out)
    cache = Path(args.cache)
    cache.mkdir(parents=True, exist_ok=True)
    out.parent.mkdir(parents=True, exist_ok=True)

    revs = json.loads(revfile.read_text())

    # Keyed on the extractor AND the attr selection, so neither can change without invalidating what is on disk.
    ehash = hashlib.sha256(EXTRACTOR.read_bytes()).hexdigest()[:8]

    if args.bin_attrs:
        selected = binary_attrs()
        # Passed by file rather than argv: the list is ~250KB of attribute names.
        allow = cache / "bin-attrs.json"
        allow.write_text(json.dumps(selected))
        attrs_expr = f"builtins.fromJSON (builtins.readFile {allow.resolve()})"
        ehash = (
            f"{ehash}.{hashlib.sha256(json.dumps(selected).encode()).hexdigest()[:8]}"
        )
        print(
            f"restricting to {len(selected):,} attrs the database says ship an executable"
        )
    else:
        attrs_expr = "null"
        ehash = f"{ehash}.all"

    if not args.merge_only:
        covered = 0
        if args.incremental and out.exists():
            covered = json.loads(out.read_text())["revisionCount"]
        targets = [
            (i, r) for i, r in enumerate(revs) if i >= covered or "narHash" not in r
        ]
        if args.limit:
            targets = targets[: args.limit]

        print(
            f"indexing {len(targets)} revisions   extractor={ehash}   threads={args.threads}"
        )
        started = time.time()
        done = failures = 0
        with futures.ThreadPoolExecutor(max_workers=args.threads) as pool:
            jobs = {
                pool.submit(
                    extract_one,
                    args.clone,
                    r["rev"],
                    attrs_expr,
                    cache,
                    ehash,
                    args.tmpdir,
                    "narHash" not in r,
                ): (i, r)
                for i, r in targets
            }
            for fut in futures.as_completed(jobs):
                i, r = jobs[fut]
                rev, narhash, err = fut.result()
                done += 1
                if narhash:
                    revs[i]["narHash"] = narhash
                if err and err != "cached":
                    failures += 1
                    print(f"  [{done}/{len(targets)}] {r['date']} {rev[:12]} {err}")
                elif done % 50 == 0:
                    rate = done / max(time.time() - started, 1)
                    left = (len(targets) - done) / max(rate, 0.001)
                    print(
                        f"  [{done}/{len(targets)}] {rate:.1f}/s, ~{left / 60:.0f}m left"
                    )
        revfile.write_text(json.dumps(revs, indent=1))
        print(
            f"extracted {done - failures}/{len(targets)} in {(time.time() - started) / 60:.1f}m, {failures} failures"
        )

    attrs = {}
    covered = 0
    if args.incremental and out.exists():
        prior = json.loads(out.read_text())
        covered, attrs = prior["revisionCount"], prior["attrs"]

    indexed = 0
    for off in range(covered, len(revs)):
        p = cache / f"{revs[off]['rev']}.{ehash}.json"
        if not p.exists():
            # Claiming coverage past a revision we never extracted would skip it for good.
            if args.incremental:
                print(
                    f"stopping at offset {off}: no extraction on disk, retry next run"
                )
                break
            continue
        indexed += 1
        for attr, version in json.loads(p.read_text()).items():
            attrs.setdefault(attr, {})[version] = off
        covered = off + 1

    if not args.incremental:
        covered = len(revs)

    out.write_text(
        json.dumps(
            {"revisionCount": covered, "attrs": attrs},
            sort_keys=True,
            separators=(",", ":"),
        )
    )
    pairs = sum(len(v) for v in attrs.values())
    print(
        f"index: {indexed} revisions merged, covering {covered}/{len(revs)}, "
        f"{len(attrs):,} attrs, {pairs:,} (attr, version) pairs"
    )
    print(f"       -> {out} ({out.stat().st_size / 1e6:.2f} MB)")


if __name__ == "__main__":
    main()
