#!/usr/bin/env python3
"""Generate the RKX trusted manifest from packaged RKX images."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import sys


MANIFEST_MAGIC = "RKXTRUST1"


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            chunk = f.read(64 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def generate_manifest(bin_dir: Path, apps: list[str]) -> str:
    lines = [MANIFEST_MAGIC]
    seen: set[str] = set()

    for app in apps:
        if app in seen:
            continue
        seen.add(app)

        rkx_path = bin_dir / f"{app}.rkx"
        if not rkx_path.exists():
            raise RuntimeError(f"missing RKX image: {rkx_path}")

        lines.append(f"/bin/{app} sha256 {hash_file(rkx_path)}")

    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bin-dir", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--apps", nargs="+", required=True)
    args = parser.parse_args()

    try:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        manifest = generate_manifest(Path(args.bin_dir), args.apps)
        out_path.write_text(manifest, encoding="ascii")
        entry_count = max(0, len(manifest.splitlines()) - 1)
        print(f"[rkx-trust] wrote {entry_count} entry(s), out={out_path}")
        return 0
    except RuntimeError as exc:
        print(f"generate_rkx_trusted_manifest.py: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
