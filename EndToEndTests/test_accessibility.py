# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Read accessibility elements through the ax and axbridge APIs.

`--api ax` reads from macOS; `--api axbridge` runs SimulatorFrameworkBridge
inside the simulator. Complete output identifies which backend served the
request. Tests select labelled Settings rows at runtime to avoid
locale-specific names. Tap and scroll tests verify navigation and movement
through axbridge. Safari is read as well, for the web content another
process is showing, which ax cannot reach. A notification delivered to an app
that is not running is followed through idb's notification commands, from
delivery until it is cleared.
"""

from __future__ import annotations

import asyncio
import json
import unittest
from typing import Any

from .documentation import documented_demo
from .harness import (
    _center,
    _elements,
    _has_area,
    _label,
    _on_screen,
    _screen,
    ACCESSIBILITY_NOT_READY_MARKER,
    ACCESSIBILITY_READY_TIMEOUT_SECONDS,
    Deadline,
    FIXTURE_APP_BUNDLE_ID,
    HarnessError,
    IdbEndToEndTestCase,
    NotReady,
    POLL_INTERVAL_SECONDS,
    Query,
    run_with_registered_cleanup,
    select_tests_for_capability,
    suite_supports,
    SuiteCapability,
    UI_UPDATE_TIMEOUT_SECONDS,
    UiWait,
    wait_until,
)

SETTINGS_BUNDLE_ID = "com.apple.Preferences"
SAFARI_BUNDLE_ID = "com.apple.mobilesafari"
GENERAL_ROW_ID = "com.apple.settings.general"
GENERAL_ROW = Query(GENERAL_ROW_ID)
SETTINGS_ROW_PREFIX = "com.apple.settings."
# Views that carry the rows' identifier prefix without being rows.
ROW_CONTAINER_TYPES = frozenset({"CollectionView", "Table", "ScrollView", "List"})
# A tap idb refused does nothing at all, so a wait long enough to catch a
# screen that did change is short.
NOTHING_OPENS_TIMEOUT_SECONDS = 2.0
MINIMUM_SCROLL_DISTANCE = 20.0

# The companion uses an exclusive simulator process for --api axbridge.
AX_BACKEND = "ax"
AXBRIDGE_BACKEND = "axbridge-exclusive"

# Exclude narrow elements such as keyboard keys and status-bar icons.
MINIMUM_CONTROL_WIDTH = 100

CONTROL_DISCOVERY_TIMEOUT_SECONDS = ACCESSIBILITY_READY_TIMEOUT_SECONDS
DESCRIBE_ALL_ARGS = ("ui", "describe-all", "--nested")

NEWS_BUNDLE_ID = "com.apple.news"
NOTIFICATION_TITLE = "Breaking"
NOTIFICATION_PAYLOAD = json.dumps(
    {
        "aps": {
            "alert": {
                "title": NOTIFICATION_TITLE,
                "body": "idb delivered this without the app running.",
            }
        }
    }
)
NOTIFICATION_STORE_TIMEOUT_SECONDS = 300.0
# A list can take over 30s, when the system doesn't answer idb and it reads
# the store instead, so a wait for the list to change allows for a few.
NOTIFICATION_LIST_TIMEOUT_SECONDS = 120.0

# Enough of a matched element to say what it is and where it sits, rather
# than every attribute a read would otherwise carry on every match.
LABEL_AND_FRAME_KEYS = ("--key", "AXLabel", "--key", "AXFrame")

SAFARI_ADDRESS_BAR_ID = "TabBarItemTitle"
# Safari names the address bar this only once it has the cursor.
SAFARI_URL_FIELD_ID = "URL"
RETURN_KEY_CODE = 40
# idb's own documentation, read by idb. Each page is long enough that what the
# demo asks for is far below what Safari has drawn, and what it asks for on the
# second one is a label inside a rendered diagram.
LIVE_ORIGIN = "https://fbidb.io"
FIRST_PAGE_PATH = "/docs/idb/fbsimulatorcontrol"
FIRST_PAGE_HEADING = "Functionality beyond Apple's tools"
# Matched without the apostrophe, so the published command does not have to
# quote its way around one.
FIRST_PAGE_MATCH = "Functionality beyond Apple"
SECOND_PAGE_PATH = "/docs/idb/accessibility"
SECOND_PAGE_LABEL = "SimulatorFrameworkBridge"


def _stand_in_page(title: str, body: str) -> str:
    """One page of the site served in place of the live one.

    Padded above the part the demo reads so that, as on the live page, what
    it asks for is below what Safari has drawn.
    """
    filler = "".join(
        f"<p>Paragraph {index}, above what this page is read for.</p>"
        for index in range(1, 60)
    )
    return (
        "<!doctype html><html lang='en'><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width, initial-scale=1'>"
        f"<title>{title}</title></head><body>{filler}{body}</body></html>"
    )


STAND_IN_PAGES = {
    FIRST_PAGE_PATH: _stand_in_page(
        "FBSimulatorControl",
        f"<h2>{FIRST_PAGE_HEADING}</h2>"
        "<p>What the framework reaches that the shipped tools do not.</p>",
    ),
    SECOND_PAGE_PATH: _stand_in_page(
        "Accessibility",
        f"<h2>{SECOND_PAGE_LABEL}</h2>"
        f"<p>A read is served by {SECOND_PAGE_LABEL}, which runs inside the "
        "simulator rather than beside it.</p>"
        "<figure><figcaption>How a read reaches axbridge</figcaption>"
        "<div style='border:1px solid #333;width:200px;padding:4px'>"
        f"<span style='font-size:7px'>{SECOND_PAGE_LABEL}</span>"
        "</div></figure>",
    ),
}


def _labelled_controls(document: Any) -> list[dict[str, Any]]:
    """Select labelled, row-width elements smaller than the largest container."""
    elements = [
        element
        for element in _elements(document)
        if _label(element) and _has_area(element)
    ]
    if not elements:
        return []
    largest = max(
        element["frame"]["width"] * element["frame"]["height"] for element in elements
    )
    return [
        element
        for element in elements
        if element["frame"]["width"] * element["frame"]["height"] < largest
        and element["frame"]["width"] >= MINIMUM_CONTROL_WIDTH
    ]


def _labels(document: Any) -> set[str]:
    return {_label(element) for element in _labelled_controls(document)}


def _visible(
    document: Any, identifier: str, element_type: str | None = None
) -> list[dict[str, Any]]:
    """Every element on screen with this identifier, and this type if one is named."""
    screen = _screen(document)
    return [
        element
        for element in _elements(document)
        if element.get("identifier") == identifier
        and (element_type is None or element.get("type") == element_type)
        and _on_screen(element, screen)
    ]


def _settings_rows(document: Any) -> list[dict[str, Any]]:
    """The Settings rows, which are the elements identified with their prefix.

    The list the rows sit in shares that prefix without being a row: its
    position never changes as it scrolls, and it is not something a scroll can
    be asked to begin from.
    """
    return [
        element
        for element in _elements(document)
        if str(element.get("identifier", "")).startswith(SETTINGS_ROW_PREFIX)
        and element.get("type") not in ROW_CONTAINER_TYPES
        and _has_area(element)
    ]


def _settings_row_positions(document: Any) -> dict[str, float]:
    """Where every row is, on the screen or off it, so movement can be measured."""
    return {
        element["identifier"]: element["frame"]["y"]
        for element in _settings_rows(document)
    }


def _settings_rows_on_screen(document: Any) -> list[str]:
    """The rows a viewer can see, from the top of the screen down."""
    screen = _screen(document)
    return [
        element["identifier"]
        for element in sorted(
            _settings_rows(document), key=lambda element: element["frame"]["y"]
        )
        if _on_screen(element, screen)
    ]


ACCESSIBILITY_READ_TESTS = frozenset(
    {
        "test_ui_describe_all_reads_both_backends_and_honours_its_options",
        "test_ui_describe_resolves_a_point_and_a_marker",
    }
)
INTERACTION_TESTS = frozenset(
    {
        "test_ui_scroll_moves_settings_rows_down_and_up",
        "test_ui_set_value_updates_the_search_field",
        "test_ui_opens_general_by_identifier_and_confirms_it",
        "test_ui_tap_opens_general_by_point",
        "test_ui_wait_returns_after_general_opens",
        "test_ui_wait_times_out_and_rejects_an_invalid_poll_interval",
        "test_a_delivered_notification_is_held_until_it_is_cleared",
        "test_web_content_is_readable_from_inside_the_simulator",
    }
)
ACCESSIBILITY_TEST_CAPABILITIES = {
    **{name: SuiteCapability.ACCESSIBILITY_READ for name in ACCESSIBILITY_READ_TESTS},
    **{name: SuiteCapability.ACCESSIBILITY_INTERACTION for name in INTERACTION_TESTS},
}


def load_tests(
    loader: unittest.TestLoader,
    tests: unittest.TestSuite,
    pattern: str | None,
) -> unittest.TestSuite:
    return select_tests_for_capability(
        loader,
        tests,
        AccessibilityTests,
        ACCESSIBILITY_TEST_CAPABILITIES,
    )


class AccessibilityTests(IdbEndToEndTestCase):
    control: dict[str, Any]

    async def asyncSetUp(self) -> None:
        required = ACCESSIBILITY_TEST_CAPABILITIES.get(self._testMethodName)
        if required is None:
            raise HarnessError(
                f"No suite capability owns {type(self).__name__}.{self._testMethodName}"
            )
        if not suite_supports(required):
            self.skipTest(
                f"{self._testMethodName} requires {required.value} capability"
            )
        await super().asyncSetUp()
        for bundle_id in (SAFARI_BUNDLE_ID, FIXTURE_APP_BUNDLE_ID, SETTINGS_BUNDLE_ID):
            await self.setup_terminate_quietly(bundle_id)
        await run_with_registered_cleanup(
            self.addAsyncCleanup,
            lambda: self.setup_terminate_quietly(SETTINGS_BUNDLE_ID),
            lambda: self.setup_idb("launch", SETTINGS_BUNDLE_ID),
        )
        self.control = await self.wait_for_control()

    async def describe_all(self, *extra: str) -> Any:
        return await self.idb_json(*DESCRIBE_ALL_ARGS, *extra)

    async def describe_all_complete(self, api: str) -> dict[str, Any]:
        document = await self.idb_json(
            "ui", "describe-all", "--api", api, "--format", "complete"
        )
        self.assertIsInstance(
            document,
            dict,
            "--format complete should report a document, not an element array",
        )
        return document

    async def wait_for_control(self) -> dict[str, Any]:
        """Wait for a labelled Settings row. Relaunch Settings if it has exited.

        Retry only an empty result or a missing translation object.
        """

        async def read() -> dict[str, Any]:
            completed = await self.idb(*DESCRIBE_ALL_ARGS, "--json", check=False)
            if completed.returncode != 0:
                if ACCESSIBILITY_NOT_READY_MARKER not in completed.error_text:
                    self.fail_or_skip_for(" ".join(DESCRIBE_ALL_ARGS), completed)
                if SETTINGS_BUNDLE_ID not in await self.simctl.running_bundle_ids():
                    await self.setup_idb("launch", SETTINGS_BUNDLE_ID, check=False)
                raise NotReady("the simulator has no accessibility translation object")
            controls = _labelled_controls(json.loads(completed.text))
            if not controls:
                raise NotReady(
                    f"Settings has no labelled rows yet; response: {completed.text}"
                )
            return controls[0]

        try:
            return await wait_until(
                "No labelled control", CONTROL_DISCOVERY_TIMEOUT_SECONDS, read
            )
        except HarnessError as error:
            self.fail(str(error))

    async def test_ui_describe_all_reads_both_backends_and_honours_its_options(
        self,
    ) -> None:
        ax = await self.describe_all_complete("ax")
        axbridge = await self.describe_all_complete("axbridge")

        self.assertEqual(ax["backend"], AX_BACKEND)
        self.assertEqual(axbridge["backend"], AXBRIDGE_BACKEND)
        for name, document in ((AX_BACKEND, ax), (AXBRIDGE_BACKEND, axbridge)):
            controls = _labelled_controls(document)
            self.assertTrue(controls, f"{name} should see Settings' rows")
        shared = _labels(ax) & _labels(axbridge)
        self.assertTrue(
            shared,
            f"the backends named no row in common; "
            f"{AX_BACKEND} saw {sorted(_labels(ax))} and "
            f"{AXBRIDGE_BACKEND} saw {sorted(_labels(axbridge))}",
        )

        selected = await self.idb_json(
            "ui",
            "describe-all",
            "--format",
            "complete",
            "--key",
            "AXLabel",
            "--key",
            "frame",
            "--profile",
            "--collect-frame-coverage",
        )
        # A frame is a dictionary too, so what is an element is what has a type.
        elements = [
            element for element in _elements(selected["elements"]) if "type" in element
        ]
        self.assertTrue(elements, "describe-all reported no elements")
        self.assertEqual(
            {key for element in elements for key in element},
            {"type", "children", "label", "frame"},
            "describe-all reported keys it was not asked for",
        )
        self.assertEqual(selected["profile"]["element_count"], len(elements))
        self.assertGreater(selected["profile"]["total_duration_ms"], 0)
        self.assertEqual(selected["frames"]["total"], len(elements))
        self.assertGreater(selected["coverage"]["frame"], 0)

    async def test_ui_describe_resolves_a_point_and_a_marker(self) -> None:
        marker = _label(self.control)
        x, y = _center(self.control)

        self.assertTrue(
            await self.idb_json("ui", "describe-point", str(x), str(y)),
            "describe-point should report the element under the point",
        )
        self.assertTrue(
            await self.idb_json("ui", "describe", marker),
            f"describe {marker!r} should report the element",
        )
        document = await self.idb_json(
            "ui", "describe", marker, "--api", "axbridge", "--format", "complete"
        )
        self.assertEqual(document["backend"], AXBRIDGE_BACKEND)
        self.assertTrue(
            _elements(document["elements"]),
            f"{AXBRIDGE_BACKEND} should resolve the marker {marker!r}",
        )

        axbridge_point = await self.idb_json(
            "ui",
            "describe-point",
            str(x),
            str(y),
            "--api",
            "axbridge",
            "--format",
            "complete",
        )
        self.assertEqual(axbridge_point["backend"], AXBRIDGE_BACKEND)
        self.assertIn(
            marker,
            [_label(element) for element in _elements(axbridge_point["elements"])],
            f"{AXBRIDGE_BACKEND} resolved {(x, y)} to something other than {marker!r}",
        )

        await self.idb_expect_failure(
            "ui",
            "describe",
            "idb-e2e-no-such-element",
            expected_error="found no element whose",
        )

    async def test_ui_wait_returns_after_general_opens(self) -> None:
        general = (await self.wait_for(GENERAL_ROW, lookup=UiWait())).element
        title = _label(general)
        self.assertTrue(title, "The General row has no label")
        before = _elements(await self.describe_all_complete("axbridge"))
        self.assertNotIn(title, [element.get("identifier") for element in before])
        marker = _label(self.control)
        for api in ("ax", "axbridge"):
            self.assertEqual(
                await self.idb_json("ui", "wait", marker, "--api", api),
                {"found": True},
                api,
            )

        async with self.idb_process(
            "ui",
            "wait",
            title,
            "--match-key",
            "AXUniqueId",
            "--timeout",
            str(UI_UPDATE_TIMEOUT_SECONDS),
            "--json",
        ) as waiting:
            await asyncio.sleep(2)
            self.assertIsNone(waiting.returncode, "wait finished before General opened")
            await self.idb("ui", "tap", GENERAL_ROW_ID, "--match-key", "AXUniqueId")
            result = await waiting.read_some(UI_UPDATE_TIMEOUT_SECONDS)
            self.assertEqual(json.loads(result), {"found": True})
            self.assertEqual(await waiting.wait_for_exit(10), 0)

        after = _elements(await self.describe_all_complete("axbridge"))
        self.assertIn(
            title,
            [
                element.get("identifier")
                for element in after
                if element.get("type") == "NavigationBar"
            ],
        )

    async def test_ui_wait_times_out_and_rejects_an_invalid_poll_interval(self) -> None:
        for backend in ("axbridge", "ax"):
            with self.subTest(backend=backend):
                completed = await self.idb_expect_failure(
                    "ui",
                    "wait",
                    "idb-e2e-no-such-element",
                    "--api",
                    backend,
                    "--timeout",
                    "1",
                    "--json",
                    expected_error="timed out after",
                )
                result = json.loads(completed.text)
                self.assertFalse(result["found"])
                self.assertIn("AXLabel", result["error"])
                self.assertIn("idb-e2e-no-such-element", result["error"])
                backend_name = "accessibility" if backend == "ax" else backend
                self.assertEqual(
                    result["error"],
                    f"The {backend_name} backend timed out after 1.0s waiting for "
                    'AXLabel containing "idb-e2e-no-such-element"; it never appeared.',
                )
                diagnostics = result["diagnostics"]
                self.assertIsNone(diagnostics["read_error"])
                self.assertTrue(diagnostics["unmatched_values"])
                self.assertTrue(
                    all(
                        isinstance(value, str)
                        for value in diagnostics["unmatched_values"]
                    )
                )
                self.assertNotIn(
                    "idb-e2e-no-such-element", diagnostics["unmatched_values"]
                )

        rejected = await self.idb_expect_failure(
            "ui",
            "wait",
            GENERAL_ROW_ID,
            "--poll-interval",
            "0",
            "--json",
            expected_error="poll_interval",
        )
        self.assertEqual(rejected.stdout, b"")

    async def wait_for_search_field(self, value: str | None = None) -> dict[str, Any]:
        async def read() -> dict[str, Any]:
            fields = [
                element
                for element in _elements(await self.describe_all_complete("axbridge"))
                if _has_area(element)
                and (
                    element.get("type") == "SearchField"
                    or (
                        element.get("type") == "TextField"
                        and element.get("subrole") == "SearchField"
                    )
                )
            ]
            if len(fields) != 1:
                raise NotReady(f"Expected one search field, found {len(fields)}")
            if value is not None and fields[0].get("value") != value:
                raise NotReady(
                    f"Search field has value {fields[0].get('value')!r}, expected {value!r}"
                )
            return fields[0]

        return await wait_until(
            "Settings search field", UI_UPDATE_TIMEOUT_SECONDS, read
        )

    async def restore_search_field(self, value: str) -> None:
        field = await self.wait_for_search_field()
        x, y = _center(field)
        await self.idb("ui", "set-value", str(x), str(y), "--value", value)

    async def test_ui_set_value_updates_the_search_field(self) -> None:
        field = await self.wait_for_search_field()
        original = field.get("value") or ""
        self.assertIsInstance(original, str)
        self.addAsyncCleanup(self.restore_search_field, original)
        x, y = _center(field)

        completed = await self.idb(
            "ui", "set-value", str(x), str(y), "--value", "idb-first"
        )

        self.assertEqual(completed.stdout, b"")
        await self.wait_for_search_field("idb-first")
        # The first write puts Settings into search mode, so the second is
        # written against a raised keyboard and a layout that has moved under it.
        field = await self.wait_for_search_field()
        x, y = _center(field)
        await self.idb("ui", "set-value", str(x), str(y), "--value", "idb-second")
        await self.wait_for_search_field("idb-second")

    async def test_ui_tap_opens_general_by_point(self) -> None:
        general = (await self.wait_for(GENERAL_ROW, lookup=UiWait())).element
        title = _label(general)
        self.assertTrue(title, "The General row has no label")

        await self.idb_expect_failure(
            "ui",
            "tap",
            GENERAL_ROW_ID,
            "--match-key",
            "AXUniqueId",
            "--expected-value",
            "idb-e2e-value-it-does-not-have",
            expected_error="before tapping",
        )
        rejected = await self.idb_expect_failure(
            "ui",
            "wait",
            title,
            "--match-key",
            "AXUniqueId",
            "--timeout",
            str(NOTHING_OPENS_TIMEOUT_SECONDS),
            "--json",
            expected_error="timed out after",
        )
        self.assertFalse(
            json.loads(rejected.text)["found"],
            "The rejected tap opened General",
        )

        general = (await self.wait_for(GENERAL_ROW, lookup=UiWait())).element
        x, y = _center(general)
        await self.idb("ui", "tap", str(x), str(y), "--api", "ax")
        await self.wait_for(Query(title, element_type="NavigationBar"), lookup=UiWait())

    async def describe_by_id(self, identifier: str, *, step: str) -> dict[str, Any]:
        """One element, read from inside the simulator by its accessibility id.

        A read addressed to the element is the read a demo can show: it answers
        with that element, its frame and the screen it sits on, rather than
        with everything the app has built.
        """
        document = await self.idb_json(
            "ui",
            "describe",
            identifier,
            "--match-key",
            "AXUniqueId",
            "--api",
            "axbridge",
            "--format",
            "complete",
            step=step,
        )
        self.assertEqual(document["backend"], AXBRIDGE_BACKEND)
        return document

    @staticmethod
    def _placed(element: dict[str, Any], screen: dict[str, float] | None) -> str:
        frame = element["frame"]
        where = (
            f"{frame['width']:.0f}×{frame['height']:.0f} points at "
            f"({frame['x']:.0f}, {frame['y']:.0f})"
        )
        if screen is None:
            return where
        return f"{where} on a {screen['width']:.0f}×{screen['height']:.0f} screen"

    @documented_demo(
        slug="open-a-settings-page-by-id",
        title="Open a Settings page by accessibility identifier",
        summary=(
            "Use an accessibility identifier to find and tap the General row "
            "in Settings without calculating screen coordinates. Then wait "
            "for the General page and read its navigation bar to verify that "
            "the tap opened the expected destination."
        ),
    )
    async def test_ui_opens_general_by_identifier_and_confirms_it(self) -> None:
        await self.wait_for(GENERAL_ROW, lookup=UiWait())

        before = await self.describe_by_id(
            GENERAL_ROW_ID, step="Find the General row by accessibility identifier"
        )
        # The row the demo opens, and the label it is published under, both come
        # from this one reading of the element the clip is showing.
        rows = _visible(before, GENERAL_ROW_ID)
        self.assertEqual(len(rows), 1, f"Expected one General row on screen: {rows}")
        title = _label(rows[0])
        self.assertTrue(title, "The General row has no label")
        self.note(
            f"The row is a {rows[0].get('type')} labelled {title!r}, with "
            f"accessibility identifier {GENERAL_ROW_ID}. It is "
            f"{self._placed(rows[0], _screen(before))}.",
            GENERAL_ROW_ID,
            title,
        )
        already_open = await self.idb_json(
            "ui", "describe-all", "--api", "axbridge", "--format", "complete"
        )
        self.assertEqual(
            _visible(already_open, title, "NavigationBar"),
            [],
            "General is already open, so the demo would show nothing opening",
        )

        self.assertEqual(
            await self.idb_json(
                "ui",
                "wait",
                GENERAL_ROW_ID,
                "--match-key",
                "AXUniqueId",
                "--api",
                "axbridge",
                "--timeout",
                str(UI_UPDATE_TIMEOUT_SECONDS),
                step="Wait until the General row is available",
            ),
            {"found": True},
        )
        self.note("The row is available, so idb can address it by identifier.", "found")

        await self.idb(
            "ui",
            "tap",
            GENERAL_ROW_ID,
            "--match-key",
            "AXUniqueId",
            step="Tap the General row by accessibility identifier",
        )
        self.note(
            "idb tapped the row by identifier; the test did not calculate a "
            "screen coordinate."
        )

        self.assertEqual(
            await self.idb_json(
                "ui",
                "wait",
                title,
                "--match-key",
                "AXUniqueId",
                "--api",
                "axbridge",
                "--timeout",
                str(UI_UPDATE_TIMEOUT_SECONDS),
                step="Wait for the General page to open",
            ),
            {"found": True},
        )
        self.note("The General page's navigation bar is now present.", "found")

        after = await self.describe_by_id(
            title, step="Verify that the General page opened"
        )
        opened = _visible(after, title, "NavigationBar")
        self.assertEqual(
            len(opened),
            1,
            f"No navigation bar named {title!r} is on screen after the tap",
        )
        self.note(
            f"The navigation bar labelled {title!r} confirms that the expected "
            f"page opened. It is {self._placed(opened[0], _screen(after))}.",
            "NavigationBar",
            title,
        )

    async def wait_for_scroll(
        self, before: dict[str, float], direction: str
    ) -> tuple[dict[str, float], dict[str, Any]]:
        """Where the rows are once the list has moved the way it was scrolled, and the reading that showed it."""

        async def read() -> tuple[dict[str, float], dict[str, Any]]:
            snapshot = await self.describe_all_complete("axbridge")
            after = _settings_row_positions(snapshot)
            movement = {
                identifier: after[identifier] - y
                for identifier, y in before.items()
                if identifier in after
            }
            if direction == "down":
                moved = any(
                    delta < -MINIMUM_SCROLL_DISTANCE for delta in movement.values()
                )
            else:
                moved = any(
                    delta > MINIMUM_SCROLL_DISTANCE for delta in movement.values()
                )
            if not moved:
                raise NotReady(f"Row movement after scrolling {direction}: {movement}")
            return after, snapshot

        return await wait_until(
            f"Settings did not scroll {direction}", UI_UPDATE_TIMEOUT_SECONDS, read
        )

    @documented_demo(
        slug="scroll-a-list",
        title="Scroll a list and verify the result",
        summary=(
            "Scroll the Settings list down from the General row and use the "
            "accessibility tree to measure how far the rows moved. Pick a "
            "visible row as the starting point for the reverse gesture, scroll "
            "back up, and measure again. This verifies the effect of each "
            "gesture instead of treating a successful command as proof that "
            "the list moved."
        ),
    )
    async def test_ui_scroll_moves_settings_rows_down_and_up(self) -> None:
        await self.wait_for(GENERAL_ROW, lookup=UiWait())
        before = _settings_row_positions(await self.describe_all_complete("axbridge"))
        self.assertIn(GENERAL_ROW_ID, before)

        await self.idb(
            "ui",
            "scroll",
            "down",
            GENERAL_ROW_ID,
            "--match-key",
            "AXUniqueId",
            step="Scroll down from the General row",
        )
        after_down, scrolled = await self.wait_for_scroll(before, "down")
        self.note(self._movement(before, after_down, "up"), GENERAL_ROW_ID)

        on_screen = _settings_rows_on_screen(scrolled)
        self.assertTrue(on_screen, "No Settings row is on screen after scrolling down")
        # A row from the middle of the screen: one at an edge can sit half
        # under the bar the list scrolls beneath, which is not where a scroll
        # can begin.
        row_after_scroll = on_screen[len(on_screen) // 2]
        self.note(
            f"{on_screen[0]} is now the top visible row. {row_after_scroll} is "
            "near the middle and can be used to start the reverse scroll.",
            row_after_scroll,
        )
        await self.idb(
            "ui",
            "scroll",
            "up",
            row_after_scroll,
            "--match-key",
            "AXUniqueId",
            step="Scroll back up from a visible row",
        )
        after_up, _ = await self.wait_for_scroll(after_down, "up")
        self.note(self._movement(after_down, after_up, "down"), row_after_scroll)

    @staticmethod
    def _movement(
        before: dict[str, float], after: dict[str, float], direction: str
    ) -> str:
        """What the rows did, read from where they were and where they are."""
        moved = {
            identifier: after[identifier] - y
            for identifier, y in before.items()
            if identifier in after
        }
        furthest = max(moved.values(), key=abs, default=0.0)
        return (
            f"{len(moved)} rows moved {direction} by as much as "
            f"{abs(furthest):.0f} points."
        )

    @staticmethod
    def _retained(text: str) -> list[tuple[str, str]]:
        """The identifier and title of each notification the system still holds."""
        held = []
        for line in text.splitlines():
            fields = [field.strip().strip('"') for field in line.split("|")]
            if len(fields) >= 3:
                held.append((fields[1], fields[2]))
        return held

    @documented_demo(
        slug="deliver-a-notification-and-watch-it-clear",
        title="Test notification delivery without handling a permission prompt",
        summary=(
            "Prepare a simulator for notification testing without launching "
            "the app or automating its permission prompt. Grant notification "
            "permission directly, deliver a push while the app is not running, "
            "and confirm that the system holds it for the app. Then clear the "
            "app's delivered notifications and verify that the system no "
            "longer holds any."
        ),
    )
    async def test_a_delivered_notification_is_held_until_it_is_cleared(self) -> None:
        self.addAsyncCleanup(self.setup_terminate_quietly, NEWS_BUNDLE_ID)
        await self.setup_terminate_quietly(NEWS_BUNDLE_ID)
        # The first push a simulator receives after it is erased waits on the
        # system building its notification store, for minutes at worst. This
        # one is sent before the permission is granted, so the system refuses
        # it and stores nothing, and the demo's own push is quick.
        await self.setup_idb(
            "send-notification",
            NEWS_BUNDLE_ID,
            NOTIFICATION_PAYLOAD,
            check=False,
            timeout=NOTIFICATION_STORE_TIMEOUT_SECONDS,
        )

        await self.idb(
            "approve",
            NEWS_BUNDLE_ID,
            "notification",
            step="Grant notification permission without showing a prompt",
        )
        self.note(
            f"Notification permission is already granted to {NEWS_BUNDLE_ID}, "
            "so the test can deliver a notification without waiting for the "
            "app to request access.",
            NEWS_BUNDLE_ID,
        )

        before = await self.idb(
            "notification",
            "list",
            NEWS_BUNDLE_ID,
            step="List notifications before delivery",
        )
        held = {identifier for identifier, _ in self._retained(before.text)}
        self.note(
            "No delivered notifications are currently stored for this app."
            if not held
            else (
                f"The system already holds {len(held)} delivered notifications "
                "for this app; the test records them so it can identify the new one."
            )
        )

        await self.idb(
            "send-notification",
            NEWS_BUNDLE_ID,
            NOTIFICATION_PAYLOAD,
            step="Deliver a notification while the app is not running",
        )

        def new_entries(text: str) -> list[str]:
            return [
                identifier
                for identifier, title in self._retained(text)
                if title == NOTIFICATION_TITLE and identifier not in held
            ]

        async def stored() -> None:
            completed = await self.setup_idb("notification", "list", NEWS_BUNDLE_ID)
            if not new_entries(completed.text):
                raise NotReady(f"{NOTIFICATION_TITLE!r} is not held yet")

        await wait_until(
            f"The system did not hold {NOTIFICATION_TITLE!r}",
            NOTIFICATION_LIST_TIMEOUT_SECONDS,
            stored,
        )

        after = await self.idb(
            "notification",
            "list",
            NEWS_BUNDLE_ID,
            step="List notifications after delivery",
        )
        delivered = new_entries(after.text)
        self.assertEqual(len(delivered), 1, f"expected one new {NOTIFICATION_TITLE!r}")
        self.note(
            f"The delivered-notification list now contains a new entry titled "
            f"{NOTIFICATION_TITLE!r}, although {NEWS_BUNDLE_ID} never ran to "
            "receive it.",
            NOTIFICATION_TITLE,
        )

        await self.idb(
            "notification",
            "clear",
            NEWS_BUNDLE_ID,
            step="Clear the app's delivered notifications",
        )

        async def released() -> None:
            completed = await self.setup_idb("notification", "list", NEWS_BUNDLE_ID)
            if self._retained(completed.text):
                raise NotReady("the system still holds notifications for the app")

        await wait_until(
            f"The system did not release the notifications for {NEWS_BUNDLE_ID}",
            NOTIFICATION_LIST_TIMEOUT_SECONDS,
            released,
        )

        cleared = await self.idb(
            "notification",
            "list",
            NEWS_BUNDLE_ID,
            step="List notifications after clearing them",
        )
        self.assertEqual(self._retained(cleared.text), [])
        self.note(
            "The delivered-notification list is empty, confirming that clearing "
            "withdrew the new entry along with any the system held before."
        )

    async def wait_for_tappable_address_bar(self) -> None:
        """Wait for the address bar to be drawn, before it is tapped.

        Safari settles its chrome for a second or two after a page arrives,
        and a marker tap resolves through ax, so the wait has to look at
        what the tap will rather than through axbridge.
        """
        await self.setup_idb(
            "ui",
            "wait",
            SAFARI_ADDRESS_BAR_ID,
            "--match-key",
            "AXUniqueId",
            "--timeout",
            str(UI_UPDATE_TIMEOUT_SECONDS),
        )

    async def wait_for_address_bar(self) -> None:
        """Wait for the address bar to take the cursor, before anything is typed."""
        await self.setup_idb(
            "ui",
            "wait",
            SAFARI_URL_FIELD_ID,
            "--match-key",
            "AXUniqueId",
            "--api",
            "axbridge",
            "--timeout",
            str(UI_UPDATE_TIMEOUT_SECONDS),
        )

    async def safari_shows_first_page(self, url: str) -> bool:
        """Whether Safari can open this address and draw the page behind it."""
        await self.setup_idb("open", url)
        arrived = await self.setup_idb(
            "ui",
            "wait",
            FIRST_PAGE_HEADING,
            "--match-key",
            "AXLabel",
            "--api",
            "axbridge",
            "--timeout",
            str(UI_UPDATE_TIMEOUT_SECONDS),
            check=False,
        )
        return arrived.returncode == 0

    async def wait_for_web_label(self, label: str) -> None:
        await self.setup_idb(
            "ui",
            "wait",
            label,
            "--match-key",
            "AXLabel",
            "--api",
            "axbridge",
            "--timeout",
            str(UI_UPDATE_TIMEOUT_SECONDS),
        )

    @documented_demo(
        slug="read-a-web-page-in-safari",
        title="Read a web page's content from inside the simulator",
        summary=(
            "Use the accessibility backend that runs inside the simulator to "
            "read a web page's own content rather than Safari's chrome. Find a "
            "single heading among the hundreds of elements the page builds, "
            "without scrolling to bring it on screen. Then navigate to a second "
            "page by typing into Safari's address bar and submitting it with a "
            "key press, and verify what loaded by finding a label drawn inside "
            "one of that page's diagrams."
        ),
    )
    async def test_web_content_is_readable_from_inside_the_simulator(self) -> None:
        self.addAsyncCleanup(self.setup_terminate_quietly, SAFARI_BUNDLE_ID)
        await self.setup_terminate_quietly(SAFARI_BUNDLE_ID)
        origin = await self.setup_web_origin(
            LIVE_ORIGIN, STAND_IN_PAGES, self.safari_shows_first_page
        )
        first_page = origin + FIRST_PAGE_PATH
        second_page = origin + SECOND_PAGE_PATH

        await self.idb("open", first_page, step="Open idb's documentation in Safari")
        await self.wait_for_web_label(FIRST_PAGE_HEADING)
        self.note("Safari has loaded the page and its content is now readable.")

        first = await self.idb_json(
            "ui",
            "describe-all",
            "--api",
            "axbridge",
            "--format",
            "complete",
            "--match",
            FIRST_PAGE_MATCH,
            *LABEL_AND_FRAME_KEYS,
            step="Find a single heading in the page's accessibility tree",
        )
        self.assertEqual(first["backend"], AXBRIDGE_BACKEND)
        headings = [
            element
            for element in _elements(first["elements"])
            if _label(element) == FIRST_PAGE_HEADING and _has_area(element)
        ]
        self.assertTrue(headings, f"no {FIRST_PAGE_HEADING!r} heading was reported")
        self.note(
            f"idb walked {first['narrowing']['walked']} elements to find the "
            f"heading, and they belong to the page rather than to Safari's "
            f"chrome. The heading is {self._placed(headings[0], _screen(first))}, "
            f"far below the visible part of the page, and no scrolling was "
            f"needed to read it.",
            FIRST_PAGE_HEADING,
            str(first["narrowing"]["walked"]),
        )

        await self.wait_for_tappable_address_bar()
        await self.idb(
            "ui",
            "tap",
            SAFARI_ADDRESS_BAR_ID,
            "--match-key",
            "AXUniqueId",
            step="Tap the address bar by accessibility identifier",
        )
        await self.wait_for_address_bar()
        self.note(
            "The address bar belongs to Safari rather than to the web page, so "
            "idb can address it by its accessibility identifier."
        )

        await self.idb(
            "ui", "text", second_page, step="Type the address of a second page"
        )
        # Typing is delivered key by key, so the field holds part of the
        # address for as long as the rest is still arriving.
        await self.setup_idb(
            "ui",
            "wait",
            second_page,
            "--match-key",
            "AXValue",
            "--api",
            "axbridge",
            "--timeout",
            str(UI_UPDATE_TIMEOUT_SECONDS),
        )
        typed = await self.idb_json(
            "ui",
            "describe",
            SAFARI_URL_FIELD_ID,
            "--match-key",
            "AXUniqueId",
            "--api",
            "axbridge",
            "--format",
            "complete",
            step="Read the address bar's value back",
        )
        fields = [
            element
            for element in _elements(typed["elements"])
            if element.get("identifier") == SAFARI_URL_FIELD_ID
        ]
        self.assertEqual([field.get("value") for field in fields], [second_page])
        self.note(
            f"The address bar holds {second_page!r}, character for character, "
            f"so every keystroke arrived.",
            second_page,
        )

        await self.idb(
            "ui",
            "key",
            str(RETURN_KEY_CODE),
            step="Submit the address with a key press",
        )
        await self.wait_for_web_label(SECOND_PAGE_LABEL)

        second = await self.idb_json(
            "ui",
            "describe-all",
            "--api",
            "axbridge",
            "--format",
            "complete",
            "--match",
            SECOND_PAGE_LABEL,
            *LABEL_AND_FRAME_KEYS,
            step="Verify that the second page loaded",
        )
        named = [
            element
            for element in _elements(second["elements"])
            if SECOND_PAGE_LABEL in _label(element) and _has_area(element)
        ]
        self.assertTrue(
            named, f"the page that loaded does not name {SECOND_PAGE_LABEL}"
        )
        smallest = min(
            named,
            key=lambda element: element["frame"]["width"] * element["frame"]["height"],
        )
        self.note(
            f"The page that loaded names {SECOND_PAGE_LABEL} in {len(named)} "
            f"places, which confirms that the typed address opened. The smallest "
            f"is {self._placed(smallest, _screen(second))}: a label drawn inside "
            f"one of the page's diagrams, which the accessibility tree reports "
            f"as an ordinary element.",
            SECOND_PAGE_LABEL,
        )
