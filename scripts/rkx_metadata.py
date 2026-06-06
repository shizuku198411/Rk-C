"""Shared helpers for RKX metadata and capability policy tools."""

from __future__ import annotations

from pathlib import Path
import re
import tomllib


REPO_ROOT = Path(__file__).resolve().parent.parent
MAKEFILE = REPO_ROOT / "Makefile"
CAPS_NIM = REPO_ROOT / "src" / "lib" / "syscall_caps.nim"

DEFAULT_STACK_PAGES = 4
MIN_STACK_PAGES = 1
MAX_STACK_PAGES = 16
MAX_ALLOWED_UIDS = 8
METADATA_VERSION = 1

CAP_CONST_RE = re.compile(
    r"^\s*(SysCap[A-Za-z0-9]+)\*\s*=\s*U32\(1'u32\s+shl\s+(\d+)\)"
)
CAP_NAME_RE = re.compile(r'^\s*(SysCap[A-Za-z0-9]+)Name\*\s*=\s*"([^"]+)"')


def load_make_names(name: str) -> list[str]:
    lines = MAKEFILE.read_text(encoding="utf-8").splitlines()
    prefix = f"{name} :="

    for idx, line in enumerate(lines):
        if not line.startswith(prefix):
            continue

        rhs = line.split(":=", 1)[1]
        while rhs.rstrip().endswith("\\") and idx + 1 < len(lines):
            rhs = rhs.rstrip()[:-1] + " "
            idx += 1
            rhs += lines[idx].strip()

        return [part for part in rhs.split() if part != "\\"]

    raise RuntimeError(f"{MAKEFILE}: missing {name}")


def load_capability_names(path: Path = CAPS_NIM) -> dict[str, str]:
    names: dict[str, str] = {}
    shifts: set[str] = set()

    with path.open("r", encoding="utf-8") as f:
        for line in f:
            cap_match = CAP_CONST_RE.match(line)
            if cap_match:
                shifts.add(cap_match.group(1))
                continue

            name_match = CAP_NAME_RE.match(line)
            if name_match:
                names[name_match.group(1)] = name_match.group(2)

    missing = sorted(shifts - set(names))
    if missing:
        joined = ", ".join(missing)
        raise RuntimeError(f"{path}: missing capability name constants for {joined}")

    if not names:
        raise RuntimeError(f"{path}: no capability definitions found")

    return names


def load_capability_bits(path: Path = CAPS_NIM) -> dict[str, int]:
    capability_names = load_capability_names(path)
    shifts: dict[str, int] = {}

    with path.open("r", encoding="utf-8") as f:
        for line in f:
            cap_match = CAP_CONST_RE.match(line)
            if cap_match:
                shifts[cap_match.group(1)] = int(cap_match.group(2))

    capability_bits: dict[str, int] = {}
    for const_name, shift in shifts.items():
        metadata_name = capability_names[const_name]
        if metadata_name in capability_bits:
            raise RuntimeError(f"{path}: duplicate capability name {metadata_name!r}")
        capability_bits[metadata_name] = 1 << shift

    if not capability_bits:
        raise RuntimeError(f"{path}: no capability definitions found")

    return capability_bits


def capability_all_known_mask(capability_bits: dict[str, int]) -> int:
    result = 0
    for bit in capability_bits.values():
        result |= bit
    return result


def app_name_from_path(path: str) -> str:
    base = Path(path).name
    if "." in base:
        base = base.rsplit(".", 1)[0]
    return base


def find_metadata_path(app_name: str, explicit_path: str | None = None) -> Path | None:
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


def metadata_path_for(kind: str, name: str) -> Path:
    return REPO_ROOT / "src" / "user" / kind / name / "rkx.toml"


def capability_mask_from_names(
    names: list[str],
    metadata_path: Path,
    capability_bits: dict[str, int],
) -> int:
    mask = 0
    for name in names:
        if name not in capability_bits:
            known = ", ".join(sorted(capability_bits.keys()))
            raise RuntimeError(
                f"{metadata_path}: unknown capability {name!r}; known: {known}"
            )
        mask |= capability_bits[name]
    return mask


def load_requested_caps(path: Path) -> set[str]:
    if not path.exists():
        raise RuntimeError(f"missing production RKX metadata: {path}")

    with path.open("rb") as f:
        data = tomllib.load(f)

    capabilities = data.get("capabilities", [])
    if not isinstance(capabilities, list):
        raise RuntimeError(f"{path}: capabilities must be a list")

    result: set[str] = set()
    for capability in capabilities:
        if not isinstance(capability, str):
            raise RuntimeError(f"{path}: capability entries must be strings")
        result.add(capability)

    return result


def load_metadata(app_name: str, explicit_path: str | None = None) -> dict[str, object]:
    capability_bits = load_capability_bits()
    metadata: dict[str, object] = {
        "stack_pages": DEFAULT_STACK_PAGES,
        "capability_mask": 0,
        "allowed_uids": [],
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
    for capability in capabilities:
        if not isinstance(capability, str):
            raise RuntimeError(f"{path}: capability entries must be strings")

    metadata["capability_mask"] = capability_mask_from_names(
        capabilities,
        path,
        capability_bits,
    )

    allowed_uids = data.get("allowed_uids", [])
    if not isinstance(allowed_uids, list):
        raise RuntimeError(f"{path}: allowed_uids must be a list")
    if len(allowed_uids) > MAX_ALLOWED_UIDS:
        raise RuntimeError(
            f"{path}: too many allowed_uids: {len(allowed_uids)} "
            f"(max {MAX_ALLOWED_UIDS})"
        )
    for uid in allowed_uids:
        if not isinstance(uid, int) or uid < 0 or uid > 0xFFFFFFFF:
            raise RuntimeError(f"{path}: invalid allowed uid {uid!r}")
    metadata["allowed_uids"] = allowed_uids
    metadata["path"] = path
    return metadata


def validate_stack_pages(value: int) -> int:
    if not isinstance(value, int):
        raise RuntimeError(f"stack pages must be an integer: {value!r}")
    if value < MIN_STACK_PAGES or value > MAX_STACK_PAGES:
        raise RuntimeError(
            f"stack pages out of range: {value} "
            f"(expected {MIN_STACK_PAGES}..{MAX_STACK_PAGES})"
        )
    return value


def validate_capability_mask(value: int) -> int:
    known_mask = capability_all_known_mask(load_capability_bits())
    if value < 0 or (value & ~known_mask) != 0:
        raise RuntimeError(
            f"unknown capability mask bits: 0x{value:x} "
            f"(known mask 0x{known_mask:x})"
        )
    return value
