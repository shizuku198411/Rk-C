#!/usr/bin/env python3
import argparse
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import tomllib

RKX_MAGIC = 0x31584B52  # "RKX1"
RKX_VERSION = 2
DEFAULT_STACK_PAGES = 4
MIN_STACK_PAGES = 1
MAX_STACK_PAGES = 16
METADATA_VERSION = 1
HEADER_SIZE = 4 * 4 + 1 * 8 + 3 * 4 * 8 + 2 * 8 + 2 * 4
# magic, version, headerSize, capabilityMask
# entryVa
# text/rodata/data: va, off, fileSize, memSize
# bss: va, memSize
# stackPages, flags

REPO_ROOT = Path(__file__).resolve().parent.parent

CAPABILITY_BITS = {
    "sys_service_manager": 1 << 0,
    "sys_raw_fs": 1 << 1,
    "sys_raw_block": 1 << 2,
    "sys_raw_net": 1 << 3,
    "sys_process_list": 1 << 4,
    "sys_process_kill": 1 << 5,
    "sys_trace_ctl": 1 << 6,
}

CAP_SERVICE_MANAGER = CAPABILITY_BITS["sys_service_manager"]
CAP_RAW_FS = CAPABILITY_BITS["sys_raw_fs"]
CAP_RAW_BLOCK = CAPABILITY_BITS["sys_raw_block"]
CAP_RAW_NET = CAPABILITY_BITS["sys_raw_net"]
CAP_PROCESS_LIST = CAPABILITY_BITS["sys_process_list"]
CAP_PROCESS_KILL = CAPABILITY_BITS["sys_process_kill"]
CAP_TRACE_CTL = CAPABILITY_BITS["sys_trace_ctl"]
CAP_ALL_KNOWN = (
    CAP_SERVICE_MANAGER
    | CAP_RAW_FS
    | CAP_RAW_BLOCK
    | CAP_RAW_NET
    | CAP_PROCESS_LIST
    | CAP_PROCESS_KILL
    | CAP_TRACE_CTL
)

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

def find_metadata_path(app_name, explicit_path=None):
    if explicit_path is not None:
        path = Path(explicit_path)
        if not path.is_absolute():
            path = REPO_ROOT / path
        return path

    candidates = [
        REPO_ROOT / "src" / "user" / "apps" / app_name / "rkx.toml",
        REPO_ROOT / "src" / "user" / "server" / app_name / "rkx.toml",
    ]
    for path in candidates:
        if path.exists():
            return path

    return None

def capability_mask_from_names(names, metadata_path):
    mask = 0
    for name in names:
        if name not in CAPABILITY_BITS:
            known = ", ".join(sorted(CAPABILITY_BITS.keys()))
            raise RuntimeError(
                f"{metadata_path}: unknown capability {name!r}; known: {known}"
            )
        mask |= CAPABILITY_BITS[name]
    return mask

def load_metadata(app_name, explicit_path=None):
    metadata = {
        "stack_pages": DEFAULT_STACK_PAGES,
        "capability_mask": 0,
        "path": None,
    }

    path = find_metadata_path(app_name, explicit_path)
    if path is None:
        return metadata
    if not path.exists():
        raise RuntimeError(f"metadata file not found: {path}")

    with path.open("rb") as f:
        data = tomllib.load(f)

    version = data.get("schema_version")
    if version != METADATA_VERSION:
        raise RuntimeError(
            f"{path}: unsupported metadata schema_version {version!r}; "
            f"expected {METADATA_VERSION}"
        )

    if "stack_pages" in data:
        metadata["stack_pages"] = data["stack_pages"]

    capabilities = data.get("capabilities", [])
    if not isinstance(capabilities, list):
        raise RuntimeError(f"{path}: capabilities must be a list")

    metadata["capability_mask"] = capability_mask_from_names(capabilities, path)
    metadata["path"] = path
    return metadata

def validate_stack_pages(value):
    if not isinstance(value, int):
        raise RuntimeError(f"stack pages must be an integer: {value!r}")
    if value < MIN_STACK_PAGES or value > MAX_STACK_PAGES:
        raise RuntimeError(
            f"stack pages out of range: {value} "
            f"(expected {MIN_STACK_PAGES}..{MAX_STACK_PAGES})"
        )
    return value

def validate_capability_mask(value):
    if value < 0 or (value & ~CAP_ALL_KNOWN) != 0:
        raise RuntimeError(
            f"unknown capability mask bits: 0x{value:x} "
            f"(known mask 0x{CAP_ALL_KNOWN:x})"
        )
    return value

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
        f"caps=0x{capability_mask:08x}"
    )

if __name__ == "__main__":
    main()
