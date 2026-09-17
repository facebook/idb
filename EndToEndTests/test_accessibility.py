# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Read Settings accessibility elements through the host and simulator APIs.

The ax API runs on the host; axbridge runs SimulatorFrameworkBridge inside
the simulator. Complete output identifies which backend served the request.
Tests select labelled Settings rows at runtime to avoid locale-specific names.
Tap and scroll tests verify navigation and movement through the simulator API.
"""

from __future__ import annotations

import asyncio
import json
import re
import unittest
from typing import Any

from .documentation import documented_demo
from .harness import (
    ACCESSIBILITY_NOT_READY_MARKER,
    ACCESSIBILITY_READY_TIMEOUT_SECONDS,
    Deadline,
    FIXTURE_APP_BUNDLE_ID,
    HarnessError,
    IdbEndToEndTestCase,
    NotReady,
    POLL_INTERVAL_SECONDS,
    run_with_registered_cleanup,
    select_tests_for_capability,
    suite_supports,
    SuiteCapability,
    wait_until,
)

SETTINGS_BUNDLE_ID = "com.apple.Preferences"
SAFARI_BUNDLE_ID = "com.apple.mobilesafari"
GENERAL_ROW_ID = "com.apple.settings.general"
UI_UPDATE_TIMEOUT_SECONDS = 30.0
MINIMUM_SCROLL_DISTANCE = 20.0

# The companion uses an exclusive simulator process for --api axbridge.
AX_BACKEND = "ax"
AXBRIDGE_BACKEND = "axbridge-exclusive"

# Exclude narrow elements such as keyboard keys and status-bar icons.
MINIMUM_CONTROL_WIDTH = 100

CONTROL_DISCOVERY_TIMEOUT_SECONDS = ACCESSIBILITY_READY_TIMEOUT_SECONDS
DESCRIBE_ALL_ARGS = ("ui", "describe-all", "--nested")


def _elements(node: Any) -> list[dict[str, Any]]:
    """Flatten flat, nested and complete accessibility output into dictionaries."""
    found: list[dict[str, Any]] = []
    if isinstance(node, dict):
        found.append(node)
        for value in node.values():
            found.extend(_elements(value))
    elif isinstance(node, list):
        for child in node:
            found.extend(_elements(child))
    return found


def _label(element: dict[str, Any]) -> str:
    """Read the label from legacy output (AXLabel) or complete output (label)."""
    for key in ("AXLabel", "label"):
        value = element.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def _has_area(element: dict[str, Any]) -> bool:
    frame = element.get("frame")
    return (
        isinstance(frame, dict)
        and bool(frame.get("width"))
        and bool(frame.get("height"))
    )


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


def _settings_row_positions(document: Any) -> dict[str, float]:
    return {
        element["identifier"]: element["frame"]["y"]
        for element in _elements(document)
        if str(element.get("identifier", "")).startswith("com.apple.settings.")
        and _has_area(element)
    }


ACCESSIBILITY_READ_TESTS = frozenset(
    {
        "test_ui_describe_all_accepts_keys_profiling_and_frame_coverage",
        "test_ui_describe_all_over_both_backends",
        "test_ui_describe_point_uses_the_guest_backend",
        "test_ui_describe_resolves_a_point_and_a_marker",
    }
)
INTERACTION_TESTS = frozenset(
    {
        "test_ui_scroll_moves_settings_rows_down_and_up",
        "test_guest_describe_runs_each_tree_reader",
        "test_guest_press_opens_general",
        "test_public_and_guest_set_value_update_the_search_field",
        "test_ui_tap_opens_general_by_marker",
        "test_ui_tap_opens_general_by_point",
        "test_ui_wait_finds_an_existing_row_on_both_backends",
        "test_ui_wait_returns_after_general_opens",
        "test_ui_wait_reports_a_missing_marker_timeout",
        "test_ui_wait_rejects_an_invalid_poll_interval",
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

    async def wait_for_settings_snapshot(self) -> dict[str, Any]:
        async def read() -> dict[str, Any]:
            args = ("ui", "describe-all", "--api", "axbridge", "--format", "complete")
            completed = await self.idb(*args, "--json", check=False)
            if completed.returncode != 0:
                if re.fullmatch(
                    r"The axbridge backend requested accessibility from the application "
                    r"with pid \d+, which did not answer in time",
                    completed.error_text.strip(),
                ):
                    raise NotReady(completed.error_text.strip())
                self.fail_or_skip_for(" ".join(args), completed)
            document = json.loads(completed.text)
            self.assertIsInstance(document, dict)
            return document

        return await wait_until(
            "Settings did not answer accessibility requests",
            UI_UPDATE_TIMEOUT_SECONDS,
            read,
        )

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

    async def wait_for_element(
        self, identifier: str, element_type: str | None = None
    ) -> dict[str, Any]:
        await self.setup_idb(
            "ui",
            "wait",
            identifier,
            "--match-key",
            "AXUniqueId",
            "--timeout",
            str(UI_UPDATE_TIMEOUT_SECONDS),
        )
        for element in _elements(await self.wait_for_settings_snapshot()):
            if element.get("identifier") == identifier and (
                element_type is None or element.get("type") == element_type
            ):
                return element
        self.fail(f"No {element_type or 'element'} with identifier {identifier!r}")

    def center(self, element: dict[str, Any]) -> tuple[int, int]:
        frame = element["frame"]
        return (
            int(frame["x"] + frame["width"] / 2),
            int(frame["y"] + frame["height"] / 2),
        )

    async def test_ui_describe_all_over_both_backends(self) -> None:
        host = await self.describe_all_complete("ax")
        bridge = await self.describe_all_complete("axbridge")

        self.assertEqual(host["backend"], AX_BACKEND)
        self.assertEqual(bridge["backend"], AXBRIDGE_BACKEND)
        for name, document in ((AX_BACKEND, host), (AXBRIDGE_BACKEND, bridge)):
            controls = _labelled_controls(document)
            self.assertTrue(controls, f"{name} should see Settings' rows")
        shared = _labels(host) & _labels(bridge)
        self.assertTrue(
            shared,
            f"the backends named no row in common; "
            f"{AX_BACKEND} saw {sorted(_labels(host))} and "
            f"{AXBRIDGE_BACKEND} saw {sorted(_labels(bridge))}",
        )

    async def test_ui_describe_all_accepts_keys_profiling_and_frame_coverage(
        self,
    ) -> None:
        document = await self.describe_all(
            "--key",
            "AXLabel",
            "--key",
            "frame",
            "--profile",
            "--collect-frame-coverage",
        )
        self.assertTrue(
            _elements(document),
            "describe-all returned no elements with the requested options",
        )

    async def test_ui_describe_resolves_a_point_and_a_marker(self) -> None:
        marker = _label(self.control)
        x, y = self.center(self.control)

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
            f"the guest bridge should resolve the marker {marker!r}",
        )

        await self.idb_expect_failure(
            "ui",
            "describe",
            "idb-e2e-no-such-element",
            expected_error="found no element whose",
        )

    async def test_ui_wait_finds_an_existing_row_on_both_backends(self) -> None:
        marker = _label(self.control)
        for api in ("ax", "axbridge"):
            result = await self.idb_json("ui", "wait", marker, "--api", api)
            self.assertEqual(result, {"found": True}, api)

    async def test_ui_wait_returns_after_general_opens(self) -> None:
        general = await self.wait_for_element(GENERAL_ROW_ID)
        title = _label(general)
        self.assertTrue(title, "The General row has no label")
        before = _elements(await self.describe_all_complete("axbridge"))
        self.assertNotIn(title, [element.get("identifier") for element in before])

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

    async def test_ui_wait_reports_a_missing_marker_timeout(self) -> None:
        completed = await self.idb_expect_failure(
            "ui",
            "wait",
            "idb-e2e-no-such-element",
            "--timeout",
            "1",
            "--json",
            expected_error="Timed out waiting for",
        )
        self.assertEqual(json.loads(completed.text), {"found": False})

    async def test_ui_wait_rejects_an_invalid_poll_interval(self) -> None:
        completed = await self.idb_expect_failure(
            "ui",
            "wait",
            GENERAL_ROW_ID,
            "--poll-interval",
            "0",
            "--json",
            expected_error="poll_interval",
        )
        self.assertEqual(completed.stdout, b"")

    async def test_ui_describe_point_uses_the_guest_backend(self) -> None:
        general = await self.wait_for_element(GENERAL_ROW_ID)
        x, y = self.center(general)

        document = await self.idb_json(
            "ui",
            "describe-point",
            str(x),
            str(y),
            "--api",
            "axbridge",
            "--format",
            "complete",
        )

        self.assertEqual(document["backend"], AXBRIDGE_BACKEND)
        self.assertIn(
            GENERAL_ROW_ID,
            [element.get("identifier") for element in _elements(document["elements"])],
        )

    async def test_guest_describe_runs_each_tree_reader(self) -> None:
        general = await self.wait_for_element(GENERAL_ROW_ID)
        pid = general["pid"]
        self.assertGreater(pid, 0)
        for options in [
            (),
            ("--snapshot-tree", "true"),
            ("--translator-vocabulary", "true"),
        ]:
            with self.subTest(options=options):
                response = json.loads(
                    (
                        await self.guest(
                            "accessibility",
                            "describe",
                            "--pid",
                            str(pid),
                            "--max-depth",
                            "2",
                            *options,
                        )
                    ).text
                )
                self.assertEqual(response["ok"], True)
                self.assertEqual(response["pid"], pid)
                self.assertIsInstance(response["tree"], dict)
                self.assertTrue(response["tree"])
                self.assertGreater(response["phases"]["mach_round_trips"], 0)

    async def test_guest_press_opens_general(self) -> None:
        general = await self.wait_for_element(GENERAL_ROW_ID)
        title = _label(general)
        self.assertTrue(title)
        x, y = self.center(general)

        response = json.loads(
            (
                await self.guest(
                    "accessibility",
                    "perform",
                    "--action",
                    "press",
                    "--pid",
                    str(general["pid"]),
                    "--x",
                    str(x),
                    "--y",
                    str(y),
                )
            ).text
        )

        self.assertEqual(response, {"ok": True, "pid": general["pid"]})
        await self.wait_for_element(title, "NavigationBar")

    async def wait_for_search_field(self, value: str | None = None) -> dict[str, Any]:
        async def read() -> dict[str, Any]:
            fields = [
                element
                for element in _elements(await self.wait_for_settings_snapshot())
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
        x, y = self.center(field)
        await self.idb("ui", "set-value", str(x), str(y), "--value", value)

    async def test_public_and_guest_set_value_update_the_search_field(self) -> None:
        field = await self.wait_for_search_field()
        original = field.get("value") or ""
        self.assertIsInstance(original, str)
        self.addAsyncCleanup(self.restore_search_field, original)
        x, y = self.center(field)

        completed = await self.idb(
            "ui", "set-value", str(x), str(y), "--value", "idb-first"
        )

        self.assertEqual(completed.stdout, b"")
        field = await self.wait_for_search_field("idb-first")
        x, y = self.center(field)
        response = json.loads(
            (
                await self.guest(
                    "accessibility",
                    "setvalue",
                    "--pid",
                    str(field["pid"]),
                    "--x",
                    str(x),
                    "--y",
                    str(y),
                    "--value",
                    "idb-second",
                )
            ).text
        )
        self.assertEqual(response, {"ok": True, "pid": field["pid"]})
        field = await self.wait_for_search_field("idb-second")
        self.assertEqual(field["value"], "idb-second")

    async def test_ui_tap_opens_general_by_point(self) -> None:
        general = await self.wait_for_element(GENERAL_ROW_ID)
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
        deadline = Deadline(UI_UPDATE_TIMEOUT_SECONDS)
        while True:
            after_rejection = await self.wait_for_settings_snapshot()
            self.assertNotIn(
                title,
                [
                    e.get("identifier")
                    for e in _elements(after_rejection)
                    if e.get("type") == "NavigationBar"
                ],
                "The rejected tap opened General",
            )
            if deadline.passed:
                break
            await asyncio.sleep(min(POLL_INTERVAL_SECONDS, deadline.remaining))

        general = await self.wait_for_element(GENERAL_ROW_ID)
        x, y = self.center(general)
        await self.idb("ui", "tap", str(x), str(y), "--api", "ax")
        await self.wait_for_element(title, "NavigationBar")

    @documented_demo(
        slug="tap-by-accessibility-id",
        title="Tap an element by its accessibility id",
        summary=(
            "Tap the General row in Settings by its accessibility id, without "
            "knowing where on the screen it is, and confirm the General page "
            "opened."
        ),
    )
    async def test_ui_tap_opens_general_by_marker(self) -> None:
        general = await self.wait_for_element(GENERAL_ROW_ID)
        title = _label(general)
        self.assertTrue(title, "The General row has no label")

        await self.idb(
            "ui",
            "tap",
            GENERAL_ROW_ID,
            "--match-key",
            "AXUniqueId",
            step="Tap the General row by its accessibility id",
        )
        await self.wait_for_element(title, "NavigationBar")

    async def wait_for_scroll(
        self, before: dict[str, float], direction: str
    ) -> dict[str, float]:
        async def read() -> dict[str, float]:
            after = _settings_row_positions(await self.wait_for_settings_snapshot())
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
            return after

        return await wait_until(
            f"Settings did not scroll {direction}", UI_UPDATE_TIMEOUT_SECONDS, read
        )

    @documented_demo(
        slug="scroll-a-list",
        title="Scroll a list and check that it moved",
        summary=(
            "Scroll the Settings list down from a named row and back up again, "
            "reading the accessibility tree to confirm the rows really moved."
        ),
    )
    async def test_ui_scroll_moves_settings_rows_down_and_up(self) -> None:
        await self.wait_for_element(GENERAL_ROW_ID)
        before = _settings_row_positions(await self.describe_all_complete("axbridge"))
        self.assertIn(GENERAL_ROW_ID, before)

        await self.idb(
            "ui",
            "scroll",
            "down",
            GENERAL_ROW_ID,
            "--match-key",
            "AXUniqueId",
            step="Scroll the Settings list down from the General row",
        )
        after_down = await self.wait_for_scroll(before, "down")

        row_after_scroll = next(iter(after_down))
        await self.idb(
            "ui",
            "scroll",
            "up",
            row_after_scroll,
            "--match-key",
            "AXUniqueId",
            step="Scroll back up from a row that is now on screen",
        )
        await self.wait_for_scroll(after_down, "up")
