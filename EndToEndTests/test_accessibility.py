# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Read Settings accessibility elements through the host and simulator APIs.

The ax API runs on the host; axbridge runs SimulatorFrameworkBridge inside
the simulator. Complete output identifies which backend served the request.
Tests select labelled Settings rows at runtime to avoid locale-specific names.
Tap and scroll tests currently check command success, not navigation results.
"""

from __future__ import annotations

import json
from typing import Any

from .harness import (
    ACCESSIBILITY_NOT_READY_MARKER,
    ACCESSIBILITY_READY_TIMEOUT_SECONDS,
    FIXTURE_APP_BUNDLE_ID,
    HarnessError,
    IdbEndToEndTestCase,
    NotReady,
    wait_until,
)

SETTINGS_BUNDLE_ID = "com.apple.Preferences"
SAFARI_BUNDLE_ID = "com.apple.mobilesafari"

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


class AccessibilityTests(IdbEndToEndTestCase):
    control: dict[str, Any]

    async def asyncSetUp(self) -> None:
        await super().asyncSetUp()
        for bundle_id in (SAFARI_BUNDLE_ID, FIXTURE_APP_BUNDLE_ID, SETTINGS_BUNDLE_ID):
            await self.terminate_quietly(bundle_id)
        await self.idb("launch", SETTINGS_BUNDLE_ID)
        self.addAsyncCleanup(self.terminate_quietly, SETTINGS_BUNDLE_ID)
        self.control = await self.some_control()

    async def describe_all(self, *extra: str) -> Any:
        return await self.idb_json(*DESCRIBE_ALL_ARGS, *extra)

    async def complete_read(self, api: str) -> dict[str, Any]:
        document = await self.idb_json(
            "ui", "describe-all", "--api", api, "--format", "complete"
        )
        self.assertIsInstance(
            document,
            dict,
            "--format complete should report a document, not an element array",
        )
        return document

    async def some_control(self) -> dict[str, Any]:
        """Wait for a labelled Settings row. Relaunch Settings if it has exited.

        Retry only an empty result or a missing translation object.
        """

        async def read() -> dict[str, Any]:
            completed = await self.idb(*DESCRIBE_ALL_ARGS, "--json", check=False)
            if completed.returncode != 0:
                if ACCESSIBILITY_NOT_READY_MARKER not in completed.error_text:
                    self.fail_or_skip_for(" ".join(DESCRIBE_ALL_ARGS), completed)
                if SETTINGS_BUNDLE_ID not in await self.simctl.running_bundle_ids():
                    await self.idb("launch", SETTINGS_BUNDLE_ID)
                raise NotReady("the simulator has no accessibility translation object")
            controls = _labelled_controls(json.loads(completed.text))
            if not controls:
                raise NotReady("Settings has put up no labelled control")
            return controls[0]

        try:
            return await wait_until(
                "No labelled control", CONTROL_DISCOVERY_TIMEOUT_SECONDS, read
            )
        except HarnessError as error:
            self.fail(str(error))

    def center(self, element: dict[str, Any]) -> tuple[int, int]:
        frame = element["frame"]
        return (
            int(frame["x"] + frame["width"] / 2),
            int(frame["y"] + frame["height"] / 2),
        )

    async def test_ui_describe_all_over_both_backends(self) -> None:
        host = await self.complete_read("ax")
        bridge = await self.complete_read("axbridge")

        self.assertEqual(host["backend"], AX_BACKEND)
        self.assertEqual(bridge["backend"], AXBRIDGE_BACKEND)
        for name, document in ((AX_BACKEND, host), (AXBRIDGE_BACKEND, bridge)):
            controls = _labelled_controls(document)
            self.assertTrue(controls, f"{name} should see Settings' rows")
            self.assertTrue(
                all(_has_area(control) for control in controls),
                f"every control {name} reports should cover a real area",
            )
        shared = _labels(host) & _labels(bridge)
        self.assertTrue(
            shared,
            f"the backends named no row in common; "
            f"{AX_BACKEND} saw {sorted(_labels(host))} and "
            f"{AXBRIDGE_BACKEND} saw {sorted(_labels(bridge))}",
        )

    async def test_ui_describe_all_accepts_key_selection_and_enrichers(self) -> None:
        document = await self.describe_all(
            "--key",
            "AXLabel",
            "--key",
            "frame",
            "--profile",
            "--collect-frame-coverage",
        )
        self.assertTrue(
            _elements(document), "an enriched read should still report elements"
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

        await self.idb_expect_failure("ui", "describe", "idb-e2e-no-such-element")

    async def test_ui_tap_by_point_and_by_marker(self) -> None:
        marker = _label(self.control)
        x, y = self.center(self.control)

        # Use a valid marker so failure comes from the expected-value check.
        await self.idb_expect_failure(
            "ui", "tap", marker, "--expected-value", "idb-e2e-value-it-does-not-have"
        )
        await self.idb("ui", "tap", str(x), str(y), "--api", "ax")
        # Return to Settings before looking up the row again.
        await self.idb("terminate", SETTINGS_BUNDLE_ID)
        await self.idb("launch", SETTINGS_BUNDLE_ID)
        await self.some_control()
        await self.idb("ui", "tap", marker)

    async def test_ui_scroll_the_frontmost_application(self) -> None:
        await self.idb("ui", "scroll", "down")
        await self.idb("ui", "scroll", "up")
