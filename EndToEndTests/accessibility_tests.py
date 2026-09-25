# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""What the accessibility tests read out of a tree, checked without a simulator.

The visibility predicate decides what a demo may claim to show: a row the tree
holds but the screen does not is not a row a recording of that screen shows.
It is checked here against a document shaped like the guest bridge's reading
of a list, including the views a real tree carries that are easy
to mistake for the screen or for a row.
"""

from __future__ import annotations

import unittest
from typing import Any

from .harness import _describe_matches, _elements, NotReady
from .test_accessibility import (
    _row_positions,
    _rows_on_screen,
    _screen,
    _search_field,
    _visible,
    GENERAL_ROW_ID,
    ROW_PREFIX,
    SEARCH_FIELD_ID,
)

LIST_ID = f"{ROW_PREFIX}list"
ACCOUNT_ROW_ID = f"{ROW_PREFIX}account"
ACCESSIBILITY_ROW_ID = f"{ROW_PREFIX}accessibility"
PRIVACY_ROW_ID = f"{ROW_PREFIX}privacy"
HIDDEN_ROW_ID = f"{ROW_PREFIX}hidden"
PLACEHOLDER_ROW_ID = f"{ROW_PREFIX}placeholder"


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


def fixture_list() -> dict[str, Any]:
    """The list as the guest bridge reads it, in the shape that misleads.

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
    table = element(
        type="CollectionView",
        identifier=LIST_ID,
        frame=frame(0, 0, 402, 874),
        children=[decoration, *rows],
    )
    navigation = element(
        type="NavigationBar", identifier="ReplHost", frame=frame(0, 62, 402, 106)
    )
    application = element(
        type="Application",
        frame=frame(0, 0, 1206, 2622),
        children=[navigation, table],
    )
    return {
        "backend": "axbridge-exclusive",
        "screen": {"coordinate_space": "screen", "width": 402, "height": 874},
        "elements": [application],
    }


def fixture_search_field() -> dict[str, Any]:
    """The search field as the guest bridge reads it in its complete format.

    A touch on the placeholder is delivered to the field, so the placeholder's
    `interactable` names the field: a reference that carries the field's
    identifier and frame without being an element of the tree.
    """
    field_frame = frame(16, 176, 370, 36)
    placeholder = element(
        type="StaticText",
        label="Search",
        frame=frame(52, 184, 60, 20),
        interactable={
            "status": "blocked",
            "reasons": [
                {
                    "kind": "handled_by",
                    "by": {
                        "type": "SearchField",
                        "identifier": SEARCH_FIELD_ID,
                        "label": None,
                        "frame": field_frame,
                        "pid": 4242,
                    },
                }
            ],
        },
    )
    field = element(
        type="SearchField",
        identifier=SEARCH_FIELD_ID,
        frame=field_frame,
        children=[placeholder],
    )
    application = element(
        type="Application", frame=frame(0, 0, 402, 874), children=[field]
    )
    return {
        "backend": "axbridge-exclusive",
        "screen": {"coordinate_space": "screen", "width": 402, "height": 874},
        "elements": [application],
    }


class ElementTests(unittest.TestCase):
    def test_reaches_every_element_of_the_tree(self) -> None:
        self.assertEqual(
            [
                element["type"]
                for element in _elements(fixture_search_field())
                if "children" in element
            ],
            ["Application", "SearchField", "StaticText"],
        )

    def test_a_reference_to_the_element_that_takes_a_touch_is_not_an_element(
        self,
    ) -> None:
        fields = [
            element
            for element in _elements(fixture_search_field())
            if element.get("identifier") == SEARCH_FIELD_ID
        ]

        self.assertEqual(len(fields), 1)


def fixture_nested_search_fields() -> dict[str, Any]:
    """Two elements carrying the search field's identifier, one inside the other."""
    field = element(
        type="SearchField",
        identifier=SEARCH_FIELD_ID,
        label="Search",
        value="",
        frame=frame(16, 176, 370, 36),
    )
    bar = element(
        type="Other",
        identifier=SEARCH_FIELD_ID,
        frame=frame(0, 168, 402, 52),
        children=[field],
    )
    table = element(type="Table", frame=frame(0, 0, 402, 874), children=[bar])
    application = element(
        type="Application", frame=frame(0, 0, 402, 874), children=[table]
    )
    return {"elements": [application]}


def fixture_search_field_reported_twice() -> dict[str, Any]:
    """The search field reported under both its container and the table.

    The accessibility runtime lists the field among the children of the search
    bar's container and of the table that holds the bar, so the guest bridge
    reports the field, and everything inside it, in both places.
    """

    def field() -> dict[str, Any]:
        glass = element(
            type="Image", identifier="magnifyingglass", frame=frame(16, 138, 20, 20)
        )
        return element(
            type="SearchField",
            identifier=SEARCH_FIELD_ID,
            label="Search",
            value="Search",
            frame=frame(8, 126, 386, 44),
            children=[glass],
        )

    container = element(
        type="_UISearchBarSearchContainerView",
        frame=frame(0, 118, 402, 60),
        children=[field()],
    )
    table = element(
        type="Table", frame=frame(0, 0, 402, 874), children=[container, field()]
    )
    application = element(
        type="Application", frame=frame(0, 0, 402, 874), children=[table]
    )
    return {"elements": [application]}


def is_search_field(element: dict[str, Any]) -> bool:
    return element.get("identifier") == SEARCH_FIELD_ID


class DescribeMatchesTests(unittest.TestCase):
    def test_places_each_match_and_what_it_sits_inside(self) -> None:
        lines = _describe_matches(
            fixture_nested_search_fields(), is_search_field
        ).splitlines()

        self.assertEqual(
            lines[:3],
            [
                "2 matching elements:",
                "  [1] under Application > Table",
                "  [2] under Application > Table > Other, a child of [1]",
            ],
        )

    def test_names_every_field_the_matches_report_differently(self) -> None:
        description = _describe_matches(fixture_nested_search_fields(), is_search_field)

        self.assertIn('  type: [1] "Other" [2] "SearchField"', description)
        self.assertIn(
            '  frame: [1] {"height": 52, "width": 402, "x": 0, "y": 168}'
            ' [2] {"height": 36, "width": 370, "x": 16, "y": 176}',
            description,
        )
        self.assertIn('  label: [1] null [2] "Search"', description)

    def test_lists_the_fields_the_matches_share_without_their_values(self) -> None:
        description = _describe_matches(fixture_nested_search_fields(), is_search_field)

        self.assertTrue(description.endswith("They agree on: identifier, hidden"))

    def test_a_match_that_is_not_inside_another_is_only_placed(self) -> None:
        document = fixture_nested_search_fields()
        table = document["elements"][0]["children"][0]
        bar = table["children"][0]
        table["children"].append(bar.pop("children")[0])

        lines = _describe_matches(document, is_search_field).splitlines()

        self.assertEqual(
            lines[1:3],
            ["  [1] under Application > Table", "  [2] under Application > Table"],
        )

    def test_a_single_match_is_described_in_full(self) -> None:
        description = _describe_matches(fixture_search_field(), is_search_field)

        self.assertEqual(
            description.splitlines()[:3],
            [
                "1 matching element:",
                "  [1] under Application",
                f'  identifier: [1] "{SEARCH_FIELD_ID}"',
            ],
        )


class SearchFieldTests(unittest.TestCase):
    def test_is_the_one_field_with_a_frame(self) -> None:
        field = _search_field(fixture_search_field())

        self.assertEqual(field["type"], "SearchField")

    def test_more_than_one_says_how_they_differ(self) -> None:
        document = fixture_nested_search_fields()
        table = document["elements"][0]["children"][0]
        table["children"].append(table["children"][0].pop("children")[0])

        with self.assertRaises(NotReady) as waiting:
            _search_field(document)

        message = str(waiting.exception)
        self.assertEqual(
            message.splitlines()[:4],
            [
                "Expected one search field with a frame, found 2; 2 matching elements:",
                "  [1] under Application > Table",
                "  [2] under Application > Table",
                "They differ in:",
            ],
        )
        self.assertIn('  type: [1] "Other" [2] "SearchField"', message)

    def test_fields_without_a_frame_are_described_but_not_counted(self) -> None:
        document = fixture_nested_search_fields()
        bar = document["elements"][0]["children"][0]["children"][0]
        bar["frame"] = None
        bar["children"][0]["frame"] = frame(0, 0, 0, 0)

        with self.assertRaises(NotReady) as waiting:
            _search_field(document)

        message = str(waiting.exception)
        self.assertIn("found 0; 2 matching elements:", message)
        self.assertIn(
            '  frame: [1] null [2] {"height": 0, "width": 0, "x": 0, "y": 0}', message
        )

    def test_one_field_reported_twice_is_the_search_field(self) -> None:
        field = _search_field(fixture_search_field_reported_twice())

        self.assertEqual(field["type"], "SearchField")


class ScreenTests(unittest.TestCase):
    def test_is_the_screen_the_document_reports(self) -> None:
        self.assertEqual(_screen(fixture_list()), frame(0.0, 0.0, 402.0, 874.0))

    def test_is_measured_by_the_largest_frame_when_none_is_reported(self) -> None:
        document = fixture_list()
        del document["screen"]

        self.assertEqual(_screen(document), frame(0, 0, 1206, 2622))

    def test_is_unknown_for_a_document_holding_no_frames(self) -> None:
        self.assertIsNone(_screen({"elements": []}))


class VisibilityTests(unittest.TestCase):
    def test_a_row_on_the_screen_is_visible(self) -> None:
        rows = _visible(fixture_list(), GENERAL_ROW_ID)

        self.assertEqual([row["label"] for row in rows], ["General"])

    def test_a_row_scrolled_off_the_screen_is_not(self) -> None:
        self.assertEqual(_visible(fixture_list(), PRIVACY_ROW_ID), [])

    def test_a_hidden_row_is_not(self) -> None:
        self.assertEqual(_visible(fixture_list(), HIDDEN_ROW_ID), [])

    def test_a_row_with_no_size_is_not(self) -> None:
        self.assertEqual(_visible(fixture_list(), PLACEHOLDER_ROW_ID), [])

    def test_holds_an_element_to_the_type_asked_for(self) -> None:
        bars = _visible(fixture_list(), "ReplHost", "NavigationBar")

        self.assertEqual([bar["type"] for bar in bars], ["NavigationBar"])
        self.assertEqual(_visible(fixture_list(), GENERAL_ROW_ID, "NavigationBar"), [])

    def test_nothing_is_visible_on_an_unknown_screen(self) -> None:
        self.assertEqual(_visible({"elements": []}, GENERAL_ROW_ID), [])


class RowTests(unittest.TestCase):
    def test_positions_leave_out_the_list_the_rows_sit_in(self) -> None:
        positions = _row_positions(fixture_list())

        self.assertNotIn(LIST_ID, positions)
        self.assertEqual(positions[GENERAL_ROW_ID], 380)

    def test_positions_keep_rows_off_the_screen_so_movement_can_be_measured(
        self,
    ) -> None:
        self.assertEqual(_row_positions(fixture_list())[PRIVACY_ROW_ID], 1500)

    def test_rows_on_screen_are_the_visible_ones_from_the_top_down(self) -> None:
        self.assertEqual(
            _rows_on_screen(fixture_list()),
            [ACCOUNT_ROW_ID, GENERAL_ROW_ID, ACCESSIBILITY_ROW_ID],
        )
