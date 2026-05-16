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


def build_image(bin_dir: str, apps: list[str]) -> bytes:
    blobs = []
    for app in apps:
        path = os.path.join(bin_dir, f"{app}.bin")
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
    parser.add_argument("--disk", required=True)
    parser.add_argument("--bin-dir", required=True)
    parser.add_argument("--apps", nargs="+", required=True)
    args = parser.parse_args()

    if not os.path.exists(args.disk):
        print(f"disk image not found: {args.disk}", file=sys.stderr)
        return 1

    image = build_image(args.bin_dir, args.apps)
    start = APPFS_START_BLOCK * BLOCK_SIZE

    with open(args.disk, "r+b") as f:
        f.seek(0, os.SEEK_END)
        disk_size = f.tell()
        if start + len(image) > disk_size:
            print("appfs image does not fit in disk image", file=sys.stderr)
            return 1
        f.seek(start)
        f.write(image)

    print(f"[appfs] packed {len(args.apps)} app(s), {len(image)} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
