# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Accessibility reads and interaction, over both backends the client can ask
for.

``--api ax`` is served by the host's accessibility API. ``--api axbridge`` is
served by ``SimulatorFrameworkBridge``, a binary the companion spawns inside
the guest to read the tree from within the simulator. The two answer the same
question by entirely different routes, so the value of these tests is that
they run the same assertions through both and require the same answer.

``--format complete`` names the backend that actually served a read, which is
the only way from outside to tell that ``--api`` was honoured rather than
quietly ignored by a companion that predates backend selection. Every backend
assertion here goes through that document.

The reads target the Settings app: a system app, so nothing is installed, with
a scrollable root and labelled rows. Markers are discovered from the tree
rather than hard-coded, so the tests do not depend on a locale or on an OS
release's wording -- but Settings always has *some* labelled rows, so
"the read came back with controls on it" is a real assertion and not a
tautology.

The reads answer for whichever application is frontmost, and on a simulator
without a display that is only unambiguous when there is one candidate. So
each test terminates every application the suite launches elsewhere, launches
Settings afresh, and waits until the tree shows Settings' own rows. That is
five commands before anything under test runs, which is why each test here is
a journey over one command surface rather than one command.

All of this needs the simulator's host to spawn inside the guest, so on a host
without ``SimLaunchHostService`` every test here skips with that reason.
"""

from __future__ import annotations

import json
from typing import Any

from .harness import (
    ACCESSIBILITY_NOT_READY_MARKER,
    FIXTURE_APP_BUNDLE_ID,
    HarnessError,
    IdbEndToEndTestCase,
    NotReady,
    wait_until,
)

SETTINGS_BUNDLE_ID = "com.apple.Preferences"
SAFARI_BUNDLE_ID = "com.apple.mobilesafari"

# The reported backend for each --api spelling. A resident companion owns its
# simulator for its whole run, so it holds its own bridge rather than the
# shared one, and the persistent request resolves to an exclusive guest.
AX_BACKEND = "ax"
AXBRIDGE_BACKEND = "axbridge-exclusive"

# Settings' rows span the screen's width; keyboard keys, status-bar items and
# icons do not, and those are the labels a smallest-first pick lands on.
MINIMUM_CONTROL_WIDTH = 100

CONTROL_DISCOVERY_TIMEOUT_SECONDS = 60.0
DESCRIBE_ALL_ARGS = ("ui", "describe-all", "--nested")


def _elements(node: Any) -> list[dict[str, Any]]:
    """Every element in an accessibility document, whichever shape it took: a
    flat list, a nested tree under ``children``, or the complete document that
    wraps either of those."""
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
    """An element's label, under whichever key the format spells it: the legacy
    element array carries the raw ``AXLabel``, the complete document a modelled
    ``label``."""
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
    """Elements with a non-blank label and a real, sub-screen frame at least a
    row wide, in document order: the plausible targets for a marker, with the
    containers that hold them excluded."""
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
    # A labelled row of the Settings screen every test reads, found once by the
    # setup that waits for the screen rather than again by each test.
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
        """A ``--format complete`` describe-all over the named backend: the
        document that reports which backend served it."""
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
        """A labelled control on screen, waiting for Settings to finish
        rendering.

        Exactly two outcomes mean not-ready-yet: a read that comes back with
        nothing labelled on it, because Settings has so far put up only its
        window, and a read that fails because the simulator has no translation
        object to serve. Every other failure is reported as one, so a host that
        cannot spawn in the guest still skips and a companion that has died is
        still named rather than waited out.
        """

        async def read() -> dict[str, Any]:
            completed = await self.idb(*DESCRIBE_ALL_ARGS, "--json", check=False)
            if completed.returncode != 0:
                if ACCESSIBILITY_NOT_READY_MARKER not in completed.error_text:
                    self.fail_or_skip_for(" ".join(DESCRIBE_ALL_ARGS), completed)
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
        """Both backends read the same screen and each says which one it is.

        The point of the bridge is that it answers the same question as the
        host API by an entirely different route, so one read from each has to
        report its own backend, see Settings' rows, and agree with the other
        about what is on screen.
        """
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
        """The three ways to name one element, and what naming nothing does."""
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

        # First, while the marker is still on the root screen and resolves, so
        # that what fails is the unmet expectation and not the lookup.
        await self.idb_expect_failure(
            "ui", "tap", marker, "--expected-value", "idb-e2e-value-it-does-not-have"
        )
        await self.idb("ui", "tap", str(x), str(y), "--api", "ax")
        # Back to the root screen, rendered, before tapping the same row by name.
        await self.idb("terminate", SETTINGS_BUNDLE_ID)
        await self.idb("launch", SETTINGS_BUNDLE_ID)
        await self.some_control()
        await self.idb("ui", "tap", marker)

    async def test_ui_scroll_the_frontmost_application(self) -> None:
        await self.idb("ui", "scroll", "down")
        await self.idb("ui", "scroll", "up")
