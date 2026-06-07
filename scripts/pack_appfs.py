#!/usr/bin/env python3
import argparse
import os
import struct
import sys

BLOCK_SIZE = 512
APPFS_MAGIC = 0x41504653
APPFS_START_BLOCK = 4096
FS_NAME_MAX = 16


def parse_extra_entry(value: str) -> tuple[str, str]:
    if "=" not in value:
        raise ValueError(f"extra entry must be NAME=PATH: {value}")
    name, path = value.split("=", 1)
    if not name:
        raise ValueError(f"extra entry name is empty: {value}")
    if not path:
        raise ValueError(f"extra entry path is empty: {value}")
    return name, path


def pad_name(name: str) -> bytes:
    raw = name.encode("ascii")
    if len(raw) >= FS_NAME_MAX:
        raise ValueError(f"name too long for appfs: {name}")
    return raw + b"\x00" * (FS_NAME_MAX - len(raw))


def build_image(bin_dir: str, apps: list[str], ext: str,
                extra_entries: list[tuple[str, str]]) -> bytes:
    blobs = []

    for app in apps:
        path = os.path.join(bin_dir, f"{app}.{ext}")
        with open(path, "rb") as f:
            blobs.append((app, f.read()))

    for name, path in extra_entries:
        with open(path, "rb") as f:
            blobs.append((name, f.read()))

    header_size = 8
    entry_size = FS_NAME_MAX + 4 + 4
    table_size = header_size + entry_size * len(blobs)

    entries = []
    payload = bytearray()

    for name, data in blobs:
        entries.append((name, table_size + len(payload), len(data)))
        payload.extend(data)

    image = bytearray()
    image.extend(struct.pack("<II", APPFS_MAGIC, len(entries)))

    for name, off, size in entries:
        image.extend(pad_name(name))
        image.extend(struct.pack("<II", off, size))

    image.extend(payload)
    return bytes(image)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--disk")
    parser.add_argument("--out-image")
    parser.add_argument("--bin-dir", required=True)
    parser.add_argument("--apps", nargs="+", required=True)
    parser.add_argument("--ext", default="bin")
    parser.add_argument("--extra-entry", action="append", default=[])
    args = parser.parse_args()

    if args.disk is None and args.out_image is None:
        print("either --disk or --out-image is required", file=sys.stderr)
        return 1

    if args.disk is not None and not os.path.exists(args.disk):
        print(f"disk image not found: {args.disk}", file=sys.stderr)
        return 1

    try:
        extra_entries = [parse_extra_entry(value) for value in args.extra_entry]
        image = build_image(args.bin_dir, args.apps, args.ext, extra_entries)
    except ValueError as exc:
        print(f"pack_appfs.py: {exc}", file=sys.stderr)
        return 1

    if args.out_image is not None:
        with open(args.out_image, "wb") as f:
            f.write(image)

        print(
            f"[appfs] wrote {len(args.apps)} app(s), "
            f"{len(extra_entries)} extra entry(s), {len(image)} bytes, "
            f"ext=.{args.ext}, out={args.out_image}"
        )

    if args.disk is None:
        return 0

    start = APPFS_START_BLOCK * BLOCK_SIZE

    with open(args.disk, "r+b") as f:
        f.seek(0, os.SEEK_END)
        disk_size = f.tell()

        if start + len(image) > disk_size:
            print("appfs image does not fit in disk image", file=sys.stderr)
            return 1

        f.seek(start)
        f.write(image)

    print(
        f"[appfs] packed {len(args.apps)} app(s), "
        f"{len(extra_entries)} extra entry(s), {len(image)} bytes, ext=.{args.ext}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
