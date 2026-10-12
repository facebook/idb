# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""The libraries package, assembled from a fake Release build."""

from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from collections.abc import Sequence
from pathlib import Path
from unittest import mock

from . import library_package

MANIFEST = {
    "libraries": {
        "Swifty": {
            "archives": ["libSwifty.a", "libCish.a"],
            "frameworks": ["Foundation.framework"],
            "linker_flags": [],
            "resources": ["libShim-iOS.dylib", "Guest.app"],
            "search_paths": ["PrivateHeaders"],
        },
        "Cish": {
            "archives": ["libCish.a"],
            "frameworks": [],
            "linker_flags": [],
            "resources": [],
            "search_paths": [],
        },
    }
}


class FakeXcodebuild:
    """Writes the XCFramework `-create-xcframework` would: one slice, the archive in it."""

    def __init__(self) -> None:
        self.commands: list[list[str]] = []

    def __call__(self, command: Sequence[str]) -> None:
        self.commands.append(list(command))
        archive = Path(command[command.index("-library") + 1])
        output = Path(command[command.index("-output") + 1])
        (output / "macos-arm64").mkdir(parents=True)
        (output / "macos-arm64" / archive.name).write_bytes(archive.read_bytes())


class LibraryPackageTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        source = self.root / "Source"
        (source / "Cish" / "include").mkdir(parents=True)
        (source / "Cish" / "include" / "module.modulemap").write_text("module Cish {}")
        (source / "PrivateHeaders" / "Private").mkdir(parents=True)
        (source / "PrivateHeaders" / "Private" / "module.modulemap").write_text(
            "module Private {}"
        )
        manifest = source / "LibraryPackage.json"
        manifest.write_text(json.dumps(MANIFEST))
        self.build = self.root / "Build"
        release = self.build / "Products" / "Release"
        simulator = self.build / "Products" / "Release-iphonesimulator"
        release.mkdir(parents=True)
        simulator.mkdir(parents=True)
        (release / "libSwifty.a").write_bytes(b"swifty")
        (release / "libCish.a").write_bytes(b"cish")
        (release / "Swifty.swiftmodule").mkdir()
        (
            release / "Swifty.swiftmodule" / "arm64-apple-macos.swiftinterface"
        ).write_text("// interface")
        (simulator / "libShim-iOS.dylib").write_bytes(b"shim")
        (simulator / "Guest.app").mkdir()
        (simulator / "Guest.app" / "Guest").write_bytes(b"guest")
        self.output = self.root / "Package"
        self.xcodebuild = FakeXcodebuild()
        patches = (
            mock.patch.object(library_package, "SOURCE_ROOT", source),
            mock.patch.object(library_package, "MANIFEST", manifest),
        )
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)

    def _assemble(self) -> None:
        library_package.assemble(self.build, self.output, self.xcodebuild)

    def test_each_library_gets_an_xcframework_with_its_module_or_headers(self) -> None:
        self._assemble()
        swifty, cish = self.xcodebuild.commands
        self.assertNotIn("-headers", swifty)
        self.assertEqual(
            cish[cish.index("-headers") + 1],
            str(self.root / "Source" / "Cish" / "include"),
        )
        self.assertTrue(
            (
                self.output
                / "Swifty.xcframework/macos-arm64/Swifty.swiftmodule/arm64-apple-macos.swiftinterface"
            ).is_file()
        )

    def test_the_package_carries_private_headers_resources_and_the_manifest(
        self,
    ) -> None:
        self._assemble()
        self.assertTrue(
            (self.output / "PrivateHeaders/Private/module.modulemap").is_file()
        )
        self.assertTrue((self.output / "Resources/libShim-iOS.dylib").is_file())
        self.assertTrue((self.output / "Resources/Guest.app/Guest").is_file())
        self.assertEqual(
            json.loads((self.output / "manifest.json").read_text()), MANIFEST
        )

    def test_a_missing_product_names_the_build_that_makes_it(self) -> None:
        (self.build / "Products" / "Release" / "libCish.a").unlink()
        with self.assertRaisesRegex(library_package.PackageError, "build libraries"):
            self._assemble()

    def test_a_previous_package_is_replaced(self) -> None:
        (self.output / "Stale.xcframework").mkdir(parents=True)
        self._assemble()
        self.assertFalse((self.output / "Stale.xcframework").exists())


if __name__ == "__main__":
    unittest.main()
