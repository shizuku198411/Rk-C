#!/usr/bin/env python3
import argparse
import os
import struct
import subprocess
import tempfile

RKX_MAGIC = 0x31584B52  # "RKX1"
RKX_VERSION = 2
DEFAULT_STACK_PAGES = 4
MIN_STACK_PAGES = 1
MAX_STACK_PAGES = 16
HEADER_SIZE = 4 * 4 + 1 * 8 + 3 * 4 * 8 + 2 * 8 + 2 * 4
# magic, version, headerSize, reserved
# entryVa
# text/rodata/data: va, off, fileSize, memSize
# bss: va, memSize
# stackPages, flags

STACK_PAGES_BY_APP = {
    "date": 1,
    "mkdir": 1,
    "rm": 1,
    "rmdir": 1,
    "kill": 1,
    "dmesg": 1,

    "ls": 2,
    "cat": 2,
    "ipc": 2,
    "svc": 2,
    "ping": 2,
    "nslookup": 2,
    "tcpcheck": 2,
    "ps": 2,
    "stracectl": 2,
    "faultcheck": 2,

    "shell": 4,
    "svcmgtd": 4,
    "procmgtd": 4,
    "blockd": 4,
    "fsd": 4,
    "procfsd": 4,

    "edit": 8,
    "curl": 8,
    "netd": 8,
}

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

def app_name_from_path(path):
    base = os.path.basename(path)
    if "." in base:
        base = base.rsplit(".", 1)[0]
    return base

def default_stack_pages(out_path):
    return STACK_PAGES_BY_APP.get(app_name_from_path(out_path), DEFAULT_STACK_PAGES)

def validate_stack_pages(value):
    if value < MIN_STACK_PAGES or value > MAX_STACK_PAGES:
        raise RuntimeError(
            f"stack pages out of range: {value} "
            f"(expected {MIN_STACK_PAGES}..{MAX_STACK_PAGES})"
        )
    return value

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--elf", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--stack-pages", type=int)
    args = parser.parse_args()
    stack_pages = validate_stack_pages(
        args.stack_pages if args.stack_pages is not None else default_stack_pages(args.out)
    )

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
        "II",
        RKX_MAGIC,
        RKX_VERSION,
        HEADER_SIZE,
        0,
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
        f"data={len(data_blob)} bss={bss_end - bss_va} stack_pages={stack_pages}"
    )

if __name__ == "__main__":
    main()
