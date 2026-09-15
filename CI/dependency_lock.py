# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Prepare and verify builds against the shared SwiftPM dependency lock."""

from __future__ import annotations

import argparse
import json
import logging
import re
from dataclasses import dataclass
from pathlib import Path

logger: logging.Logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class Pin:
    location: str
    version: str
    revision: str


def repository_url(location: str) -> str:
    return location.rstrip("/").removesuffix(".git").lower()


def load_pins(path: Path) -> dict[str, Pin]:
    document = json.loads(path.read_text())
    if (
        not isinstance(document, dict)
        or document.get("version") not in (2, 3)
        or not document.get("pins")
    ):
        raise ValueError(f"{path}: expected a nonempty SwiftPM v2/v3 lockfile")
    pins: dict[str, Pin] = {}
    for entry in document["pins"]:
        identity = entry["identity"]
        state = entry["state"]
        if not isinstance(state, dict):
            raise ValueError(f"{path}: {identity}: expected a state object")
        revision = state.get("revision", "")
        version = state.get("version", "")
        if (
            entry.get("kind") != "remoteSourceControl"
            or re.fullmatch(r"[0-9a-f]{40}", revision) is None
            or re.fullmatch(r"\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.+-]+)?", version) is None
        ):
            raise ValueError(f"{path}: {identity} must pin a version and git revision")
        if identity in pins:
            raise ValueError(f"{path}: duplicate dependency {identity}")
        pins[identity] = Pin(repository_url(entry["location"]), version, revision)
    return pins


def verify_resolved(expected_path: Path, actual_path: Path) -> None:
    expected = load_pins(expected_path)
    actual = load_pins(actual_path)
    differences = []
    for identity in sorted(expected.keys() | actual.keys()):
        if identity not in actual:
            differences.append(f"{identity}: missing from resolved graph")
        elif identity not in expected:
            differences.append(f"{identity}: absent from shared lockfile")
        elif actual[identity] != expected[identity]:
            differences.append(
                f"{identity}: expected {expected[identity]}, resolved {actual[identity]}"
            )
    if differences:
        raise ValueError(
            f"{actual_path} differs from {expected_path}:\n" + "\n".join(differences)
        )


def prepare_codegen(lock_path: Path, destination: Path) -> None:
    pins = load_pins(lock_path)
    dependencies = []
    for identity in ("grpc-swift-2", "grpc-swift-protobuf", "swift-protobuf"):
        if identity not in pins:
            raise ValueError(f"{lock_path}: missing codegen dependency {identity}")
        pin = pins[identity]
        dependencies.append(
            f"    .package(url: {json.dumps(pin.location + '.git')}, "
            f"exact: {json.dumps(pin.version)}),"
        )
    # The normal idb manifest needs generated sources before SwiftPM can load it.
    manifest = (
        "// swift-tools-version:6.1\nimport PackageDescription\n"
        'let package = Package(name: "idb-codegen", dependencies: [\n'
        + "\n".join(dependencies)
        + "\n], targets: [])\n"
    )
    destination.mkdir(parents=True, exist_ok=True)
    for name, content in (
        ("Package.swift", manifest.encode()),
        ("Package.resolved", lock_path.read_bytes()),
    ):
        path = destination / name
        if not path.exists() or path.read_bytes() != content:
            path.write_bytes(content)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare-codegen", "check"))
    parser.add_argument("lock", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "prepare-codegen":
            prepare_codegen(args.lock, args.destination)
        else:
            verify_resolved(args.lock, args.destination)
    except (OSError, ValueError, KeyError, TypeError) as error:
        logger.error("%s", error)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
