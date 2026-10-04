# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Build install fixtures, archive them, and describe a tree so two can be compared.

Fixtures are generated rather than checked in, so they carry only system
binaries and deterministic content and can be built on any Mac.
"""

from __future__ import annotations

import enum
import hashlib
import os
import plistlib
import random
import shutil
import stat
import subprocess
import unicodedata
import zipfile
from dataclasses import dataclass
from pathlib import Path

# Any Mach-O passes the companion's architecture check on a Mac.
EXECUTABLE = Path("/usr/bin/true")
LARGE_FILE_BYTES = 8 * 1024 * 1024
MANY_FILES = 200


class Kind(enum.Enum):
    APP = ("install",)
    XCTEST = ("xctest", "install")
    FRAMEWORK = ("framework", "install")
    DYLIB = ("dylib", "install")
    DSYM = ("dsym", "install")

    def __init__(self, *subcommand: str) -> None:
        self.subcommand = subcommand

    @property
    def storage(self) -> str:
        """The folder of the companion's auxiliary directory this kind is stored in."""
        return {
            Kind.APP: "idb-applications",
            Kind.XCTEST: "idb-test-bundles",
            Kind.FRAMEWORK: "idb-frameworks",
            Kind.DYLIB: "idb-dylibs",
            Kind.DSYM: "idb-dsyms",
        }[self]


class Archive(enum.Enum):
    NONE = "none"
    IPA_STORED = "ipa-stored"
    IPA_DEFLATED = "ipa-deflated"
    IPA_DITTO = "ipa-ditto"
    TGZ = "tgz"
    TZST = "tzst"

    @property
    def suffix(self) -> str:
        return {
            Archive.NONE: "",
            Archive.IPA_STORED: ".ipa",
            Archive.IPA_DEFLATED: ".ipa",
            Archive.IPA_DITTO: ".ipa",
            Archive.TGZ: ".tar.gz",
            Archive.TZST: ".tar.zst",
        }[self]


@dataclass(frozen=True)
class Directory:
    pass


@dataclass(frozen=True)
class Link:
    target: str


@dataclass(frozen=True)
class File:
    sha256: str
    executable: bool


Entry = Directory | Link | File


def describe(root: Path) -> dict[str, Entry]:
    """Every entry under `root` by its NFC-normalized relative path.

    Normalized because APFS keeps whichever form a name was written in, and
    an extractor may write the other.
    """
    entries: dict[str, Entry] = {}
    for path in sorted(root.rglob("*")):
        name = unicodedata.normalize("NFC", str(path.relative_to(root)))
        mode = path.lstat().st_mode
        if stat.S_ISLNK(mode):
            entries[name] = Link(os.readlink(path))
        elif stat.S_ISDIR(mode):
            entries[name] = Directory()
        else:
            entries[name] = File(
                hashlib.sha256(path.read_bytes()).hexdigest(),
                bool(mode & stat.S_IXUSR),
            )
    return entries


def differences(expected: dict[str, Entry], actual: dict[str, Entry]) -> list[str]:
    lines = [f"missing {name}" for name in sorted(expected.keys() - actual.keys())]
    lines += [f"unexpected {name}" for name in sorted(actual.keys() - expected.keys())]
    lines += [
        f"{name}: expected {expected[name]}, got {actual[name]}"
        for name in sorted(expected.keys() & actual.keys())
        if expected[name] != actual[name]
    ]
    return lines


def _write_plist(path: Path, contents: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(plistlib.dumps(contents))


def _write(path: Path, contents: bytes, mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(contents)
    path.chmod(mode)


def _executable(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(EXECUTABLE, path)
    path.chmod(0o755)


def _kitchen_sink(root: Path) -> None:
    """Content an extractor can get wrong: links, modes, names, sizes and counts."""
    rng = random.Random(root.name)
    (root / "Nested" / "Empty").mkdir(parents=True)
    _write(root / "Nested" / "Ünïcødé ✓.txt", "unicode\n".encode())
    _write(root / "With Space" / "file", b"space\n")
    _write(root / "Nested" / "zero", b"")
    _write(root / "Scripts" / "run.sh", b"#!/bin/sh\nexit 0\n", 0o755)
    _write(root / "Large.bin", rng.randbytes(LARGE_FILE_BYTES))
    for index in range(MANY_FILES):
        _write(root / "Many" / f"{index:03}.txt", rng.randbytes(512))
    _write(root / "Versions" / "A" / "file", b"versioned\n")
    (root / "Versions" / "Current").symlink_to("A")
    (root / "Nested" / "link.plist").symlink_to("../Info.plist")
    # An extended attribute makes `ditto --sequesterRsrc` write __MACOSX entries.
    subprocess.run(
        [
            "xattr",
            "-w",
            "com.example.extraction",
            "value",
            str(root / "With Space" / "file"),
        ],
        check=True,
    )


def build(kind: Kind, directory: Path, bundle_id: str) -> Path:
    """Build a fixture of `kind` in `directory`, returning the path to install."""
    directory.mkdir(parents=True, exist_ok=True)
    match kind:
        case Kind.APP:
            bundle = directory / "Sink.app"
            _executable(bundle / "Sink")
            _write_plist(
                bundle / "Info.plist",
                {
                    "CFBundleIdentifier": bundle_id,
                    "CFBundleExecutable": "Sink",
                    "CFBundleName": "Sink",
                },
            )
            _kitchen_sink(bundle)
            return bundle
        case Kind.XCTEST:
            bundle = directory / "Sample.xctest"
            _executable(bundle / "Sample")
            _write_plist(
                bundle / "Info.plist",
                {
                    "CFBundleIdentifier": bundle_id,
                    "CFBundleExecutable": "Sample",
                    "CFBundleName": "Sample",
                    "CFBundlePackageType": "BNDL",
                },
            )
            _write(bundle / "Resources" / "data.txt", b"resource\n")
            (bundle / "Resources" / "link.txt").symlink_to("data.txt")
            return bundle
        case Kind.FRAMEWORK:
            bundle = directory / "Sample.framework"
            version = bundle / "Versions" / "A"
            _executable(version / "Sample")
            _write_plist(
                version / "Resources" / "Info.plist",
                {
                    "CFBundleIdentifier": bundle_id,
                    "CFBundleExecutable": "Sample",
                    "CFBundleName": "Sample",
                    "CFBundlePackageType": "FMWK",
                },
            )
            (bundle / "Versions" / "Current").symlink_to("A")
            (bundle / "Sample").symlink_to("Versions/Current/Sample")
            (bundle / "Resources").symlink_to("Versions/Current/Resources")
            return bundle
        case Kind.DYLIB:
            dylib = directory / "libSample.dylib"
            _executable(dylib)
            return dylib
        case Kind.DSYM:
            bundle = directory / "Sample.dSYM"
            _write_plist(
                bundle / "Contents" / "Info.plist",
                {
                    "CFBundleIdentifier": f"com.apple.xcode.dsym.{bundle_id}",
                    "CFBundlePackageType": "dSYM",
                },
            )
            _write(
                bundle / "Contents" / "Resources" / "DWARF" / "Sample",
                random.Random(bundle_id).randbytes(64 * 1024),
            )
            return bundle


def _ipa(root: Path, destination: Path, compression: int) -> None:
    """Write `root` under Payload/ keeping modes and symlinks, as ditto does."""
    with zipfile.ZipFile(destination, "w", compression=compression) as archive:
        for path in sorted([root, *root.rglob("*")]):
            name = str(Path("Payload", path.relative_to(root.parent)))
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                info = zipfile.ZipInfo(name)
                info.external_attr = mode << 16
                archive.writestr(info, os.readlink(path))
            elif stat.S_ISDIR(mode):
                info = zipfile.ZipInfo(name + "/")
                info.external_attr = (mode << 16) | 0x10
                archive.writestr(info, b"")
            else:
                archive.write(path, name, compress_type=compression)


def archive(bundle: Path, kind: Archive, directory: Path) -> Path:
    """Package `bundle` as `kind` in `directory`."""
    destination = directory / f"{bundle.name}{kind.suffix}"
    match kind:
        case Archive.NONE:
            return bundle
        case Archive.IPA_STORED:
            _ipa(bundle, destination, zipfile.ZIP_STORED)
        case Archive.IPA_DEFLATED:
            _ipa(bundle, destination, zipfile.ZIP_DEFLATED)
        case Archive.IPA_DITTO:
            payload = directory / "ditto" / "Payload"
            payload.mkdir(parents=True)
            subprocess.run(
                ["ditto", str(bundle), str(payload / bundle.name)], check=True
            )
            subprocess.run(
                [
                    "ditto",
                    "-c",
                    "-k",
                    "--sequesterRsrc",
                    "--keepParent",
                    str(payload),
                    str(destination),
                ],
                check=True,
            )
        case Archive.TGZ:
            subprocess.run(
                [
                    "tar",
                    "-czf",
                    str(destination),
                    "-C",
                    str(bundle.parent),
                    bundle.name,
                ],
                check=True,
            )
        case Archive.TZST:
            subprocess.run(
                [
                    "tar",
                    "--zstd",
                    "-cf",
                    str(destination),
                    "-C",
                    str(bundle.parent),
                    bundle.name,
                ],
                check=True,
            )
    return destination
