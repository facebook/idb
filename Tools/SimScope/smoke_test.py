# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Exercise the downloadable bundle without requiring a GUI or booted simulator."""

import os
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path


class SimScopeSmokeTests(unittest.TestCase):
    def test_relocated_app(self) -> None:
        source = Path(os.environ["SIMSCOPE_APP"])
        with tempfile.TemporaryDirectory(prefix="simscope smoke ") as directory:
            app = Path(directory) / "SimScope.app"
            subprocess.run(["ditto", "--noextattr", str(source), str(app)], check=True)
            subprocess.run(
                ["codesign", "--verify", "--deep", "--strict", str(app)], check=True
            )
            with (app / "Contents/Info.plist").open("rb") as stream:
                info = plistlib.load(stream)
            self.assertEqual(info["CFBundleIdentifier"], "com.facebook.simscope")
            binaries = app / "Contents/MacOS"
            for tool, arguments in (
                (info["CFBundleExecutable"], ["--check-installation"]),
                ("idb_companion", ["--help"]),
                ("idb-repl", ["--help"]),
                ("simscope-remote", ["--help"]),
            ):
                with self.subTest(tool=tool):
                    result = subprocess.run(
                        [str(binaries / tool), *arguments],
                        cwd=directory,
                        env={**os.environ, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"},
                        capture_output=True,
                        text=True,
                        timeout=60,
                    )
                    self.assertEqual(
                        result.returncode, 0, result.stdout + result.stderr
                    )
                    self.assertTrue(result.stdout or result.stderr)


if __name__ == "__main__":
    unittest.main()
