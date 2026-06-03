#!/usr/bin/env python3
import argparse
import os
import struct
import sys

BLOCK_SIZE = 512
APPFS_MAGIC = 0x41504653
APPFS_START_BLOCK = 4096
FS_NAME_MAX = 16


def pad_name(name: str) -> bytes:
    raw = name.encode("ascii")
    if len(raw) >= FS_NAME_MAX:
        raise ValueError(f"name too long for appfs: {name}")
    return raw + b"\x00" * (FS_NAME_MAX - len(raw))


def build_image(bin_dir: str, apps: list[str], ext: str) -> bytes:
    blobs = []

    for app in apps:
        path = os.path.join(bin_dir, f"{app}.{ext}")
        with open(path, "rb") as f:
            blobs.append((app, f.read()))

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
    args = parser.parse_args()

    if args.disk is None and args.out_image is None:
        print("either --disk or --out-image is required", file=sys.stderr)
        return 1

    if args.disk is not None and not os.path.exists(args.disk):
        print(f"disk image not found: {args.disk}", file=sys.stderr)
        return 1

    image = build_image(args.bin_dir, args.apps, args.ext)

    if args.out_image is not None:
        with open(args.out_image, "wb") as f:
            f.write(image)

        print(f"[appfs] wrote {len(args.apps)} app(s), {len(image)} bytes, ext=.{args.ext}, out={args.out_image}")

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

    print(f"[appfs] packed {len(args.apps)} app(s), {len(image)} bytes, ext=.{args.ext}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
