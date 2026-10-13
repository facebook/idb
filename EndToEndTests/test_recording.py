# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""A recording followed through a rotation of the simulator.

Not one of the website's demos, which are performed on GitHub's hosted runners: their CoreSimulator cannot report
the display configuration a recording follows a rotation by, so there it is skipped.
"""

from __future__ import annotations

import struct
import unittest
from pathlib import Path
from typing import Any

from .harness import (
    _screen,
    NotReady,
    select_tests_for_capability,
    SuiteCapability,
    UI_UPDATE_TIMEOUT_SECONDS,
    wait_until,
)
from .recording import BAR_POINTS
from .test_accessibility import _visible, AccessibilityFixtureTestCase, GENERAL_ROW_ID

ROTATION_RECORDING_CAPABILITIES = {
    "test_record_through_a_rotation": SuiteCapability.ACCESSIBILITY_READ,
}


def load_tests(
    loader: unittest.TestLoader,
    tests: unittest.TestSuite,
    pattern: str | None,
) -> unittest.TestSuite:
    return select_tests_for_capability(
        loader,
        loader.loadTestsFromTestCase(RotationRecordingTests),
        RotationRecordingTests,
        ROTATION_RECORDING_CAPABILITIES,
    )


HIGHLIGHT_RGBA = [255, 59, 48, 0.45]


def _png_size(path: Path) -> tuple[int, int]:
    """A PNG's width and height, from its header."""
    with path.open("rb") as png:
        header = png.read(24)
    width, height = struct.unpack(">II", header[16:24])
    return width, height


class RotationRecordingTests(AccessibilityFixtureTestCase):
    capabilities = ROTATION_RECORDING_CAPABILITIES

    async def general_row(self, *, step: str, landscape: bool) -> dict[str, Any]:
        """The General row once the screen it is read from has the orientation asked for."""

        async def read() -> dict[str, Any]:
            document = await self.idb_json(
                "ui",
                "describe",
                GENERAL_ROW_ID,
                "--match-key",
                "AXUniqueId",
                "--api",
                "axbridge",
                "--format",
                "complete",
            )
            screen = _screen(document)
            if screen is None or (screen["width"] > screen["height"]) != landscape:
                raise NotReady(f"the screen is still {screen}")
            rows = _visible(document, GENERAL_ROW_ID)
            if len(rows) != 1:
                raise NotReady(f"expected one General row on screen: {rows}")
            return document

        await wait_until(
            "the General row in the new orientation", UI_UPDATE_TIMEOUT_SECONDS, read
        )
        return await self.idb_json(
            "ui",
            "describe",
            GENERAL_ROW_ID,
            "--match-key",
            "AXUniqueId",
            "--api",
            "axbridge",
            "--format",
            "complete",
            step=step,
        )

    def highlight(self, document: dict[str, Any]) -> dict[str, float]:
        assert self.recording is not None
        frame = _visible(document, GENERAL_ROW_ID)[0]["frame"]
        self.recording.send(
            "overlay",
            overlays=[
                {
                    "rectangle": {
                        "x": frame["x"],
                        "y": frame["y"] + BAR_POINTS,
                        "width": frame["width"],
                        "height": frame["height"],
                        "rgba": HIGHLIGHT_RGBA,
                    }
                }
            ],
        )
        return frame

    async def recorded_shape(self) -> tuple[int, int]:
        assert self.recording is not None
        screenshot = await self.recording.screenshot()
        self.assertIsNotNone(screenshot, "The recorder took no screenshot")
        assert screenshot is not None
        return _png_size(screenshot)

    async def test_record_through_a_rotation(self) -> None:
        """Record the simulator with bars above and below the screen, highlight a row at
        the frame accessibility reports for it, then rotate to landscape and back,
        highlighting the row again each time. The recording keeps its portrait frame, as
        a video file cannot change size, and letterboxes the landscape screen into it
        upright: the bars stay across the top and bottom, and the highlight lands on the
        row wherever it is laid out. The recorder's screenshot shows the screen as the
        interface does, landscape in landscape."""
        if self.recording is None:
            raise unittest.SkipTest(
                "The recorder is not running, so there is no recording to rotate"
            )
        if not self.recording.reads_display_configuration():
            raise unittest.SkipTest(
                "The recorder cannot read this simulator's display configuration, so it "
                "records the screen as laid out when recording began and cannot follow "
                "a rotation"
            )
        self.addAsyncCleanup(self.setup_idb, "rotation", "PORTRAIT")
        self.addCleanup(
            lambda: self.recording and self.recording.send("overlay", overlays=[])
        )

        portrait = await self.general_row(
            step="Find the General row in portrait", landscape=False
        )
        frame = self.highlight(portrait)
        width, height = await self.recorded_shape()
        self.assertLess(width, height)
        self.note(
            f"The row is {frame['width']:.0f}×{frame['height']:.0f} points at "
            f"({frame['x']:.0f}, {frame['y']:.0f}), and the recording is "
            f"{width}×{height} pixels: portrait, with its bars.",
            GENERAL_ROW_ID,
        )

        await self.idb(
            "rotation", "LANDSCAPE_LEFT", step="Rotate the simulator to landscape"
        )
        landscape = await self.general_row(
            step="Find the General row in landscape", landscape=True
        )
        turned = self.highlight(landscape)
        turned_width, turned_height = await self.recorded_shape()
        self.assertGreater(turned_width, turned_height)
        self.note(
            f"In landscape the row is {turned['width']:.0f}×{turned['height']:.0f} "
            f"points at ({turned['x']:.0f}, {turned['y']:.0f}). The recording keeps "
            "its portrait frame, with the landscape screen letterboxed upright inside "
            "it and the bars still across the top and bottom; the recorder's "
            f"screenshot is the screen itself, {turned_width}×{turned_height} pixels.",
            GENERAL_ROW_ID,
        )

        await self.idb("rotation", "PORTRAIT", step="Rotate back to portrait")
        upright = await self.general_row(
            step="Find the General row in portrait again", landscape=False
        )
        self.highlight(upright)
        self.assertEqual(await self.recorded_shape(), (width, height))
        self.note(
            f"Back in portrait, the screen fills the {width}×{height} recording again.",
            GENERAL_ROW_ID,
        )
