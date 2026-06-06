#!/usr/bin/env python3
"""Validate production RKX capability requests against kernel trusted grants."""

from __future__ import annotations

from pathlib import Path
import re
import sys

from rkx_metadata import (
    REPO_ROOT,
    load_capability_names,
    load_make_names,
    load_requested_caps,
    metadata_path_for,
)

TRUSTED_CAPS_NIM = REPO_ROOT / "src" / "kernel" / "task" / "trusted_caps.nim"


def parse_trusted_cap_grants(capability_names: dict[str, str]) -> dict[str, set[str]]:
    text = TRUSTED_CAPS_NIM.read_text(encoding="utf-8")
    start = text.find("const TrustedCapPathGrants")
    if start < 0:
        raise RuntimeError(f"{TRUSTED_CAPS_NIM}: missing TrustedCapPathGrants")

    end = text.find("## Converts", start)
    if end < 0:
        end = len(text)

    body = text[start:end]
    grants: dict[str, set[str]] = {}

    for match in re.finditer(r"trustedCapGrant\((.*?)\)", body, re.DOTALL):
        grant_body = match.group(1)
        path_match = re.search(r'cstring"([^"]+)"', grant_body)
        if not path_match:
            raise RuntimeError(f"{TRUSTED_CAPS_NIM}: trusted grant without path")

        path = path_match.group(1)
        caps: set[str] = set()
        for const_name in re.findall(r"\bSysCap[A-Za-z0-9]+\b", grant_body):
            if const_name not in capability_names:
                raise RuntimeError(
                    f"{TRUSTED_CAPS_NIM}: unknown capability constant {const_name}"
                )
            caps.add(capability_names[const_name])

        if path in grants:
            raise RuntimeError(f"{TRUSTED_CAPS_NIM}: duplicate trusted path {path}")
        grants[path] = caps

    return grants


def production_metadata_paths() -> dict[str, Path]:
    result: dict[str, Path] = {}
    for app in load_make_names("USER_APP_NAMES"):
        result[f"/bin/{app}"] = metadata_path_for("apps", app)
    for server in load_make_names("USER_SERVER_NAMES"):
        result[f"/bin/{server}"] = metadata_path_for("server", server)
    return result


def validate() -> None:
    capability_names = load_capability_names()
    known_names = set(capability_names.values())
    trusted_grants = parse_trusted_cap_grants(capability_names)
    metadata_paths = production_metadata_paths()
    failures: list[str] = []

    for path, metadata_path in sorted(metadata_paths.items()):
        requested = load_requested_caps(metadata_path)
        unknown = requested - known_names
        if unknown:
            failures.append(
                f"{metadata_path}: unknown capabilities: {', '.join(sorted(unknown))}"
            )
            continue

        trusted = trusted_grants.get(path, set())
        if requested != trusted:
            failures.append(
                f"{metadata_path}: requested {sorted(requested)} but trusted "
                f"{sorted(trusted)} for {path}"
            )

    for path in sorted(trusted_grants):
        if path not in metadata_paths:
            failures.append(f"{TRUSTED_CAPS_NIM}: trusted path is not packaged: {path}")

    if failures:
        print("rkx capability policy mismatch:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        raise SystemExit(1)

    print(
        "rkx capability policy ok "
        f"({len(metadata_paths)} production metadata files, "
        f"{len(trusted_grants)} trusted grants)"
    )


def main() -> None:
    try:
        validate()
    except RuntimeError as exc:
        print(f"validate_rkx_caps.py: {exc}", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
