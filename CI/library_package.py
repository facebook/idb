# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Assemble the published libraries package from a Release build.

    python3 -m CI.library_package <build-directory> <output-directory>

The package holds everything a consumer of idb's libraries needs, as
`LibraryPackage.json` describes it:

    <output>/
      <Library>.xcframework   the static archive, with its Swift module (and
                              module interface) or, for a C library, its headers
      PrivateHeaders/         the vendored private frameworks' module maps, and
                              the TBD stubs the linker flags name
      Resources/              the guest bridges and shims the libraries run
      manifest.json           LibraryPackage.json: what each library links and needs

Stdlib only: CI runs it with the runner's own python3.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from collections.abc import Callable, Sequence
from pathlib import Path

SOURCE_ROOT = Path(__file__).resolve().parent.parent
MANIFEST = SOURCE_ROOT / "LibraryPackage.json"
# Where each SDK's Release products land under the build directory's Products/.
PRODUCT_DIRECTORIES = ("Release", "Release-iphonesimulator", "Release-appletvsimulator")

Runner = Callable[[Sequence[str]], None]


class PackageError(Exception):
    pass


def _run(command: Sequence[str]) -> None:
    subprocess.run(command, check=True)


def _find_product(products: Path, name: str) -> Path:
    for directory in PRODUCT_DIRECTORIES:
        candidate = products / directory / name
        if candidate.exists():
            return candidate
    raise PackageError(f"{name} was not built; run './build.sh build libraries' first")


def _xcframework(name: str, products: Path, output: Path, run: Runner) -> Path:
    """One library's XCFramework: its archive, then its module or headers in the slice."""
    archive = _find_product(products, f"lib{name}.a")
    xcframework = output / f"{name}.xcframework"
    command = ["xcodebuild", "-create-xcframework", "-library", str(archive)]
    headers = SOURCE_ROOT / name / "include"
    if headers.is_dir():
        command += ["-headers", str(headers)]
    run(command + ["-output", str(xcframework)])
    module = archive.parent / f"{name}.swiftmodule"
    if module.is_dir():
        # A library slice's Swift module sits beside its archive, where SwiftPM and
        # Xcode look for it. Recent Xcodes copy it there themselves; older ones copy
        # only the archive and headers.
        slices = [path for path in xcframework.iterdir() if path.is_dir()]
        if len(slices) != 1:
            raise PackageError(f"{xcframework} has {len(slices)} slices, expected one")
        if not (slices[0] / module.name).exists():
            shutil.copytree(module, slices[0] / module.name)
    return xcframework


def assemble(
    build_directory: Path, output: Path, run: Runner = _run
) -> dict[str, object]:
    manifest = json.loads(MANIFEST.read_text())
    libraries: dict[str, dict[str, list[str]]] = manifest["libraries"]
    products = build_directory / "Products"
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    for name in libraries:
        _xcframework(name, products, output, run)
    shutil.copytree(SOURCE_ROOT / "PrivateHeaders", output / "PrivateHeaders")
    resources = output / "Resources"
    resources.mkdir()
    for name in sorted(
        {item for entry in libraries.values() for item in entry["resources"]}
    ):
        product = _find_product(products, name)
        if product.is_dir():
            shutil.copytree(product, resources / name, symlinks=True)
        else:
            shutil.copy2(product, resources / name)
    shutil.copy2(MANIFEST, output / "manifest.json")
    return manifest


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("build_directory", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args(argv)
    try:
        manifest = assemble(args.build_directory, args.output)
    except PackageError as error:
        print(f"error: {error}")
        return 1
    print(f"Packaged {len(manifest['libraries'])} libraries into {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
