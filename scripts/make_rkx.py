#!/usr/bin/env python3
import argparse
import os
import struct
import subprocess
import tempfile

from rkx_metadata import (
    MAX_ALLOWED_UIDS,
    app_name_from_path,
    load_metadata,
    validate_capability_mask,
    validate_stack_pages,
)

RKX_MAGIC = 0x31584B52  # "RKX1"
RKX_VERSION = 2
HEADER_SIZE = 4 * 4 + 1 * 8 + 3 * 4 * 8 + 2 * 8 + 4 * 4 + MAX_ALLOWED_UIDS * 4
# magic, version, headerSize, capabilityMask
# entryVa
# text/rodata/data: va, off, fileSize, memSize
# bss: va, memSize
# stackPages, flags
# allowedUidCount, reserved, allowedUids

def read_symbols(elf):
    out = subprocess.check_output(["llvm-nm", "-n", elf], text=True)
    syms = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 3:
            try:
                addr = int(parts[0], 16)
            except ValueError:
                continue
            name = parts[2]
            syms[name] = addr
    return syms

def dump_section(elf, section, out_path):
    subprocess.run([
        "llvm-objcopy",
        "-O", "binary",
        f"--only-section={section}",
        elf,
        out_path,
    ], check=True)

    if not os.path.exists(out_path):
        return b""

    with open(out_path, "rb") as f:
        return f.read()

def need(syms, name):
    if name not in syms:
        raise RuntimeError(f"missing symbol: {name}")
    return syms[name]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--elf", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--metadata")
    parser.add_argument("--stack-pages", type=int)
    parser.add_argument("--capability-mask", type=lambda x: int(x, 0))
    args = parser.parse_args()
    app_name = app_name_from_path(args.out)
    metadata = load_metadata(app_name, args.metadata)
    stack_pages = validate_stack_pages(
        args.stack_pages if args.stack_pages is not None else metadata["stack_pages"]
    )
    capability_mask = validate_capability_mask(
        args.capability_mask
        if args.capability_mask is not None
        else metadata["capability_mask"]
    )
    allowed_uids = list(metadata["allowed_uids"])
    allowed_uid_count = len(allowed_uids)
    while len(allowed_uids) < MAX_ALLOWED_UIDS:
        allowed_uids.append(0)

    syms = read_symbols(args.elf)

    entry = need(syms, "user_entry")

    text_va = need(syms, "__user_text_start")
    text_end = need(syms, "__user_text_end")
    ro_va = need(syms, "__user_rodata_start")
    ro_end = need(syms, "__user_rodata_end")
    data_va = need(syms, "__user_data_start")
    data_end = need(syms, "__user_data_end")
    bss_va = need(syms, "__user_bss_start")
    bss_end = need(syms, "__user_bss_end")

    with tempfile.TemporaryDirectory() as td:
        text = os.path.join(td, "text.bin")
        rodata = os.path.join(td, "rodata.bin")
        data = os.path.join(td, "data.bin")

        dump_section(args.elf, ".text", text)
        dump_section(args.elf, ".rodata", rodata)
        dump_section(args.elf, ".data", data)

        with open(text, "rb") as f:
            text_blob = f.read()
        with open(rodata, "rb") as f:
            ro_blob = f.read()
        with open(data, "rb") as f:
            data_blob = f.read()

    off = HEADER_SIZE
    text_off = off
    off += len(text_blob)

    ro_off = off
    off += len(ro_blob)

    data_off = off
    off += len(data_blob)

    header = struct.pack(
        "<IIII"
        "Q"
        "QQQQ"
        "QQQQ"
        "QQQQ"
        "QQ"
        "II"
        "II"
        "IIIIIIII",
        RKX_MAGIC,
        RKX_VERSION,
        HEADER_SIZE,
        capability_mask,
        entry,

        text_va,
        text_off,
        len(text_blob),
        text_end - text_va,

        ro_va,
        ro_off,
        len(ro_blob),
        ro_end - ro_va,

        data_va,
        data_off,
        len(data_blob),
        data_end - data_va,

        bss_va,
        bss_end - bss_va,

        stack_pages,
        0,

        allowed_uid_count,
        0,
        *allowed_uids,
    )

    assert len(header) == HEADER_SIZE

    image = bytearray()
    image.extend(header)
    image.extend(text_blob)
    image.extend(ro_blob)
    image.extend(data_blob)

    with open(args.out, "wb") as f:
        f.write(image)

    print(
        f"[rkx] {args.out}: text={len(text_blob)} rodata={len(ro_blob)} "
        f"data={len(data_blob)} bss={bss_end - bss_va} stack_pages={stack_pages} "
        f"caps=0x{capability_mask:08x} allowed_uids={metadata['allowed_uids']}"
    )

if __name__ == "__main__":
    main()
