# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import io
import os
import tempfile
import unittest
from pathlib import Path

from .install_bench import (
    Bench,
    build_fixture,
    Companion,
    http_server,
    PATTERNS,
    run_matrix,
)


class InstallBenchEndToEndTests(unittest.IsolatedAsyncioTestCase):
    """Every install pattern succeeds against a source-built companion, directly and over a remote-like link.

    Needs a booted simulator, so `unittest discover` does not collect it (it matches no `*_tests.py`):
    `DEVICE_UDID=... DEVICE_SET_PATH=... IDB_E2E_COMPANION_PATH=... IDB_BIN=... python3 -m unittest Benchmarks.install_bench_end_to_end`.
    """

    async def test_every_pattern_installs(self) -> None:
        udid = os.environ["DEVICE_UDID"]
        device_set = Path(os.environ["DEVICE_SET_PATH"])
        companion_path = Path(os.environ["IDB_E2E_COMPANION_PATH"])
        work = Path(tempfile.mkdtemp())
        base_app = companion_path.parent / "Resources" / "ReplHost.app"
        fixtures = [build_fixture(base_app, work, size, 64, 0.6) for size in (1, 16)]
        with http_server(work) as http_port:
            companion = Companion(companion_path, udid, device_set, work)
            try:
                bench = Bench(
                    "e2e",
                    Path(os.environ["IDB_BIN"]),
                    companion,
                    udid,
                    device_set,
                    work,
                    http_port,
                    120,
                )
                records = await run_matrix(
                    bench,
                    fixtures,
                    ["none", "remote"],
                    list(PATTERNS.values()),
                    1,
                    io.StringIO(),
                )
            finally:
                companion.stop()
        # Patterns that fail today, with the outcome they fail with.
        broken: dict[str, str] = {}
        failures = [
            f"{r['fixture']} {r['scenario']} {r['pattern']}: {r['outcome']} {r['error']}"
            for r in records
            if r["outcome"] != "ok" and r["pattern"] not in broken
        ]
        self.assertEqual(failures, [], "\n" + "\n".join(failures))
        self.assertEqual(
            {(r["pattern"], r["outcome"]) for r in records if r["pattern"] in broken},
            set(broken.items()),
        )
        self.assertGreaterEqual(len(records), 2 * (3 + 2 * 5))
