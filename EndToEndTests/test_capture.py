# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Check PNG output and read the simulator log while the command runs."""

from __future__ import annotations

import unittest

from .harness import IdbEndToEndTestCase, select_tests_for_capability, SuiteCapability

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"

SETTINGS_BUNDLE_ID = "com.apple.Preferences"

LOG_TIMEOUT_SECONDS = 60.0

CAPTURE_TEST_CAPABILITIES = {
    "test_log_streams_simulator_output": SuiteCapability.LONG_LIVED_STREAM,
    "test_screenshot_writes_a_png_to_a_file_and_to_stdout": SuiteCapability.ARTIFACT_PUBLICATION,
}


def load_tests(
    loader: unittest.TestLoader,
    tests: unittest.TestSuite,
    pattern: str | None,
) -> unittest.TestSuite:
    return select_tests_for_capability(
        loader,
        tests,
        CaptureTests,
        CAPTURE_TEST_CAPABILITIES,
    )


class CaptureTests(IdbEndToEndTestCase):
    async def test_screenshot_writes_a_png_to_a_file_and_to_stdout(self) -> None:
        destination = self.make_temporary_directory() / "screen.png"

        await self.idb("screenshot", str(destination))

        written = destination.read_bytes()
        self.assertEqual(written[: len(PNG_SIGNATURE)], PNG_SIGNATURE)
        self.assertGreater(
            len(written), len(PNG_SIGNATURE), "PNG output contains only the signature"
        )

        to_stdout = (await self.idb("screenshot", "-")).stdout
        self.assertEqual(to_stdout[: len(PNG_SIGNATURE)], PNG_SIGNATURE)
        self.assertGreater(
            len(to_stdout),
            len(PNG_SIGNATURE),
            "PNG output contains only the signature",
        )

    async def test_log_streams_simulator_output(self) -> None:
        async with self.idb_process("log") as log:
            # The setup client owns both the stimulus and its cleanup.
            self.addAsyncCleanup(self.setup_terminate_quietly, SETTINGS_BUNDLE_ID)
            await self.setup_terminate_quietly(SETTINGS_BUNDLE_ID)
            await self.setup_idb("launch", SETTINGS_BUNDLE_ID)

            self.assertTrue(
                (await log.read_some(LOG_TIMEOUT_SECONDS)).strip(),
                "log should have streamed the target's own output",
            )
            self.assertIsNone(
                log.returncode, "log should still be streaming when it is read"
            )
