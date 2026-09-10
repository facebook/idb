# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""What the target puts out: a picture of its screen, and its log.

Both are bytes rather than a model, so the assertion in each case is that what
arrived is the thing itself -- a PNG that starts with PNG's signature, a log
stream that is actually streaming -- rather than that a command exited zero.

`screenshot` writes to a file or, for `-`, to stdout, and the two paths encode
separately. `log` is one of the streaming commands: it does not finish, so it
is read while it runs and stopped afterwards.
"""

from __future__ import annotations

from .harness import IdbEndToEndTestCase

# The eight bytes every PNG begins with.
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"

SETTINGS_BUNDLE_ID = "com.apple.Preferences"

# The simulator's log is busy, but only once something is happening on it.
LOG_TIMEOUT_SECONDS = 60.0


class CaptureTests(IdbEndToEndTestCase):
    async def test_screenshot_writes_a_png_to_a_file_and_to_stdout(self) -> None:
        destination = self.make_temporary_directory() / "screen.png"

        await self.idb("screenshot", str(destination))

        written = destination.read_bytes()
        self.assertEqual(written[: len(PNG_SIGNATURE)], PNG_SIGNATURE)
        self.assertGreater(
            len(written), len(PNG_SIGNATURE), "a screenshot is more than its signature"
        )

        to_stdout = (await self.idb("screenshot", "-")).stdout
        self.assertEqual(to_stdout[: len(PNG_SIGNATURE)], PNG_SIGNATURE)
        self.assertGreater(
            len(to_stdout),
            len(PNG_SIGNATURE),
            "a screenshot is more than its signature",
        )

    async def test_log_streams_the_targets_log(self) -> None:
        async with self.idb_process("log") as log:
            # Something has to happen on the simulator for it to have anything
            # to say, so the stream is given traffic to carry. Launching is
            # refused outright for an application that is already running, and
            # nothing here resets the simulator between tests, so what another
            # test left behind is stopped first.
            self.addAsyncCleanup(self.terminate_quietly, SETTINGS_BUNDLE_ID)
            await self.terminate_quietly(SETTINGS_BUNDLE_ID)
            await self.idb("launch", SETTINGS_BUNDLE_ID)

            self.assertTrue(
                (await log.read_some(LOG_TIMEOUT_SECONDS)).strip(),
                "log should have streamed the target's own output",
            )
            self.assertIsNone(
                log.returncode, "log should still be streaming when it is read"
            )
