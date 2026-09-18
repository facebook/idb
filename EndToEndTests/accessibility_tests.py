# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""What the accessibility tests read out of a tree, checked without a simulator.

The visibility predicate decides what a demo may claim to show: a row the tree
holds but the screen does not is not a row a recording of that screen shows.
It is checked here against a document shaped like the guest bridge's reading
of the Settings list, including the views a real tree carries that are easy
to mistake for the screen or for a row.
"""

from __future__ import annotations

import unittest
from typing import Any

from .test_accessibility import (
    _screen,
    _settings_row_positions,
    _settings_rows_on_screen,
    _visible,
    GENERAL_ROW_ID,
)

LIST_ID = "com.apple.settings.sidebar.collectionView"
ACCOUNT_ROW_ID = "com.apple.settings.primaryAppleAccount"
ACCESSIBILITY_ROW_ID = "com.apple.settings.accessibility"
PRIVACY_ROW_ID = "com.apple.settings.privacy"
HIDDEN_ROW_ID = "com.apple.settings.hidden"
PLACEHOLDER_ROW_ID = "com.apple.settings.placeholder"


def frame(x: float, y: float, width: float, height: float) -> dict[str, float]:
    return {"x": x, "y": y, "width": width, "height": height}


def element(**fields: Any) -> dict[str, Any]:
    described: dict[str, Any] = {
        "children": [],
        "identifier": None,
        "label": None,
        "type": "Other",
        "frame": None,
        "hidden": None,
    }
    described.update(fields)
    return described


def settings_list() -> dict[str, Any]:
    """The Settings list as the guest bridge reads it, in the shape that misleads.

    The application's frame is reported in pixels, so it is the largest frame
    without being the screen. The list's background decoration extends well
    above the window. The list itself carries the rows' identifier prefix. One
    row is scrolled below the screen, one is hidden, and one has no size.
    """
    rows = [
        element(
            type="Button",
            identifier=ACCOUNT_ROW_ID,
            label="Apple Account",
            frame=frame(16, 168, 370, 102),
        ),
        element(
            type="Button",
            identifier=GENERAL_ROW_ID,
            label="General",
            frame=frame(16, 380, 370, 52),
        ),
        element(
            type="Button",
            identifier=ACCESSIBILITY_ROW_ID,
            label="Accessibility",
            frame=frame(16, 432, 370, 52),
        ),
        element(
            type="Button",
            identifier=PRIVACY_ROW_ID,
            label="Privacy & Security",
            frame=frame(16, 1500, 370, 52),
        ),
        element(
            type="Button",
            identifier=HIDDEN_ROW_ID,
            label="Hidden",
            frame=frame(16, 484, 370, 52),
            hidden=True,
        ),
        element(
            type="Button",
            identifier=PLACEHOLDER_ROW_ID,
            label="Placeholder",
            frame=frame(16, 536, 0, 0),
        ),
    ]
    decoration = element(
        type="_UICollectionViewListLayoutSectionBackgroundColorDecorationView",
        frame=frame(-16, -1580, 434, 1856),
    )
    settings = element(
        type="CollectionView",
        identifier=LIST_ID,
        frame=frame(0, 0, 402, 874),
        children=[decoration, *rows],
    )
    navigation = element(
        type="NavigationBar", identifier="Settings", frame=frame(0, 62, 402, 106)
    )
    application = element(
        type="Application",
        frame=frame(0, 0, 1206, 2622),
        children=[navigation, settings],
    )
    return {
        "backend": "axbridge-exclusive",
        "screen": {"coordinate_space": "screen", "width": 402, "height": 874},
        "elements": [application],
    }


class ScreenTests(unittest.TestCase):
    def test_is_the_screen_the_document_reports(self) -> None:
        self.assertEqual(_screen(settings_list()), frame(0.0, 0.0, 402.0, 874.0))

    def test_is_measured_by_the_largest_frame_when_none_is_reported(self) -> None:
        document = settings_list()
        del document["screen"]

        self.assertEqual(_screen(document), frame(0, 0, 1206, 2622))

    def test_is_unknown_for_a_document_holding_no_frames(self) -> None:
        self.assertIsNone(_screen({"elements": []}))


class VisibilityTests(unittest.TestCase):
    def test_a_row_on_the_screen_is_visible(self) -> None:
        rows = _visible(settings_list(), GENERAL_ROW_ID)

        self.assertEqual([row["label"] for row in rows], ["General"])

    def test_a_row_scrolled_off_the_screen_is_not(self) -> None:
        self.assertEqual(_visible(settings_list(), PRIVACY_ROW_ID), [])

    def test_a_hidden_row_is_not(self) -> None:
        self.assertEqual(_visible(settings_list(), HIDDEN_ROW_ID), [])

    def test_a_row_with_no_size_is_not(self) -> None:
        self.assertEqual(_visible(settings_list(), PLACEHOLDER_ROW_ID), [])

    def test_holds_an_element_to_the_type_asked_for(self) -> None:
        bars = _visible(settings_list(), "Settings", "NavigationBar")

        self.assertEqual([bar["type"] for bar in bars], ["NavigationBar"])
        self.assertEqual(_visible(settings_list(), GENERAL_ROW_ID, "NavigationBar"), [])

    def test_nothing_is_visible_on_an_unknown_screen(self) -> None:
        self.assertEqual(_visible({"elements": []}, GENERAL_ROW_ID), [])


class RowTests(unittest.TestCase):
    def test_positions_leave_out_the_list_the_rows_sit_in(self) -> None:
        positions = _settings_row_positions(settings_list())

        self.assertNotIn(LIST_ID, positions)
        self.assertEqual(positions[GENERAL_ROW_ID], 380)

    def test_positions_keep_rows_off_the_screen_so_movement_can_be_measured(
        self,
    ) -> None:
        self.assertEqual(_settings_row_positions(settings_list())[PRIVACY_ROW_ID], 1500)

    def test_rows_on_screen_are_the_visible_ones_from_the_top_down(self) -> None:
        self.assertEqual(
            _settings_rows_on_screen(settings_list()),
            [ACCOUNT_ROW_ID, GENERAL_ROW_ID, ACCESSIBILITY_ROW_ID],
        )
