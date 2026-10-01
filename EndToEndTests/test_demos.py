# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""The demos the website publishes.

Each test here is a documented demo (see `documentation.py`): the commands it
names with `step=` are the demo's published transcript, and its notes say what
the output shows. A demo may tell a story across several commands; nothing
relies on one for coverage, since each behaviour it shows is also checked by a
targeted test beside the other tests of its command.
"""

from __future__ import annotations

import unittest
from typing import Any

from .documentation import documented_demo
from .harness import (
    _center,
    _elements,
    _has_area,
    _label,
    _screen,
    IdbEndToEndTestCase,
    NotReady,
    select_tests_for_capability,
    SuiteCapability,
    UI_UPDATE_TIMEOUT_SECONDS,
    wait_until,
)
from .test_accessibility import (
    _row_movement,
    _row_positions,
    _rows_on_screen,
    _visible,
    AccessibilityFixtureTestCase,
    AXBRIDGE_BACKEND,
    FIRST_PAGE_HEADING,
    FIRST_PAGE_MATCH,
    FIRST_PAGE_PATH,
    GENERAL_ROW_ID,
    LABEL_AND_FRAME_KEYS,
    LIVE_ORIGIN,
    RETURN_KEY_CODE,
    SAFARI_ADDRESS_BAR_ID,
    SAFARI_BUNDLE_ID,
    SAFARI_URL_FIELD_ID,
    SafariTestCase,
    SECOND_PAGE_LABEL,
    SECOND_PAGE_PATH,
    STAND_IN_PAGES,
)
from .test_services import (
    _retained_notifications,
    NEWS_BUNDLE_ID,
    NOTIFICATION_LIST_TIMEOUT_SECONDS,
    NOTIFICATION_PAYLOAD,
    NOTIFICATION_STORE_TIMEOUT_SECONDS,
    NOTIFICATION_TITLE,
)

ACCESSIBILITY_DEMO_CAPABILITIES = {
    "test_scroll_by_element": SuiteCapability.ACCESSIBILITY_INTERACTION,
    "test_tap_by_accessibility_id": SuiteCapability.ACCESSIBILITY_INTERACTION,
}
WEB_CONTENT_DEMO_CAPABILITIES = {
    "test_read_web_content_in_safari": SuiteCapability.ACCESSIBILITY_INTERACTION,
}


def load_tests(
    loader: unittest.TestLoader,
    tests: unittest.TestSuite,
    pattern: str | None,
) -> unittest.TestSuite:
    return unittest.TestSuite(
        [
            *(
                select_tests_for_capability(
                    loader, loader.loadTestsFromTestCase(case), case, requirements
                )
                for case, requirements in (
                    (AccessibilityDemos, ACCESSIBILITY_DEMO_CAPABILITIES),
                    (WebContentDemos, WEB_CONTENT_DEMO_CAPABILITIES),
                )
            ),
            loader.loadTestsFromTestCase(NotificationDemos),
        ]
    )


def _placed(element: dict[str, Any], screen: dict[str, float] | None) -> str:
    frame = element["frame"]
    where = (
        f"{frame['width']:.0f}×{frame['height']:.0f} points at "
        f"({frame['x']:.0f}, {frame['y']:.0f})"
    )
    if screen is None:
        return where
    return f"{where} on a {screen['width']:.0f}×{screen['height']:.0f} screen"


def _notifications(count: int) -> str:
    return f"{count} delivered notification{'' if count == 1 else 's'}"


class AccessibilityDemos(AccessibilityFixtureTestCase):
    capabilities = ACCESSIBILITY_DEMO_CAPABILITIES

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

    @documented_demo(
        slug="tap-by-accessibility-id",
        title="Tap an element by its accessibility identifier",
        summary=(
            "Tap a list's General row by naming its accessibility identifier. "
            "idb finds the element in the accessibility tree and activates it "
            "directly, so there are no screen coordinates to calculate, and "
            "the tap still lands if the layout, device size or scroll position "
            "changes. The General page opens."
        ),
    )
    async def test_tap_by_accessibility_id(self) -> None:
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
            f"{_placed(rows[0], _screen(before))}.",
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
            ),
            {"found": True},
        )

        await self.idb(
            "ui",
            "tap",
            GENERAL_ROW_ID,
            "--match-key",
            "AXUniqueId",
            step="Tap the General row by accessibility identifier",
        )
        x, y = _center(rows[0])
        self.note(
            f"idb resolved {GENERAL_ROW_ID} to the row's centre, ({x}, {y}), "
            "and pressed it.",
            GENERAL_ROW_ID,
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
            ),
            {"found": True},
        )

        after = await self.describe_by_id(
            title, step="Read the navigation bar of the page that opened"
        )
        opened = _visible(after, title, "NavigationBar")
        self.assertEqual(
            len(opened),
            1,
            f"No navigation bar named {title!r} is on screen after the tap",
        )
        self.note(
            f"The navigation bar reads {title!r}. It is "
            f"{_placed(opened[0], _screen(after))}.",
            "NavigationBar",
            title,
        )

    @documented_demo(
        slug="scroll-by-element",
        title="Scroll a list from an element, without pixel math",
        summary=(
            "Scroll a list down by naming its General row's accessibility "
            "identifier, then back up from a row that scrolled into view. idb "
            "performs the platform's page-scroll action on the list that "
            "contains the element, so there are no swipe coordinates, "
            "velocities or inertial deceleration to account for. Reading the "
            "accessibility tree before and after each scroll shows how far "
            "every row moved."
        ),
    )
    async def test_scroll_by_element(self) -> None:
        before = _row_positions(await self.describe_all_complete("axbridge"))
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

        on_screen = _rows_on_screen(scrolled)
        self.assertTrue(on_screen, "No row is on screen after scrolling down")
        # A row from the middle of the screen: one at an edge can sit half
        # under the bar the list scrolls beneath, which is not where a scroll
        # can begin.
        row_after_scroll = on_screen[len(on_screen) // 2]
        self.note(
            f"{on_screen[0]} is now the top row on screen. The scroll back up "
            f"starts from {row_after_scroll}, near the middle of the screen.",
            row_after_scroll,
        )
        await self.idb(
            "ui",
            "scroll",
            "up",
            row_after_scroll,
            "--match-key",
            "AXUniqueId",
            step=f"Scroll back up from {row_after_scroll}",
        )
        after_up, _ = await self.wait_for_scroll(after_down, "up")
        self.note(self._movement(after_down, after_up, "down"), row_after_scroll)

    @staticmethod
    def _movement(
        before: dict[str, float], after: dict[str, float], direction: str
    ) -> str:
        """What the rows did, read from where they were and where they are."""
        distances = [abs(delta) for delta in _row_movement(before, after).values()]
        if not distances:
            return "No row is in both readings."
        shortest, longest = min(distances), max(distances)
        if longest - shortest <= 1:
            return f"All {len(distances)} rows moved {direction} {longest:.0f} points."
        return (
            f"{len(distances)} rows moved {direction} between {shortest:.0f} "
            f"and {longest:.0f} points."
        )


class WebContentDemos(SafariTestCase):
    capabilities = WEB_CONTENT_DEMO_CAPABILITIES

    @documented_demo(
        slug="read-web-content-in-safari",
        title="Read and navigate web content in Safari, including off-screen elements",
        summary=(
            "Read a web page's own elements, not just Safari's toolbar, and "
            "find a heading several screens below the visible area without "
            "scrolling to it. Then type a new address into Safari's address "
            "bar, submit it with a key press, and find a label drawn inside "
            "one of the new page's diagrams."
        ),
    )
    async def test_read_web_content_in_safari(self) -> None:
        origin = await self.setup_web_origin(
            LIVE_ORIGIN, STAND_IN_PAGES, self.safari_shows_first_page
        )
        # Choosing the origin leaves Safari on the first page, and the clip
        # has to open it from the home screen.
        await self.setup_terminate_quietly(SAFARI_BUNDLE_ID)
        await self.setup_idb("ui", "button", "HOME")
        first_page = origin + FIRST_PAGE_PATH
        second_page = origin + SECOND_PAGE_PATH

        await self.idb("open", first_page, step="Open idb's documentation in Safari")
        await self.wait_for_web_label(FIRST_PAGE_HEADING)

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
        screen = _screen(first)
        assert screen is not None
        heading_y = headings[0]["frame"]["y"]
        self.note(
            f"idb searched {first['narrowing']['walked']} elements of the page "
            f"and found the heading at y={heading_y:.0f}, about "
            f"{round(heading_y / screen['height'])} screens down the page. "
            "Nothing was scrolled.",
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
            f"Safari's address bar has accessibility identifier "
            f"{SAFARI_ADDRESS_BAR_ID}, so idb taps it like any native control.",
            SAFARI_ADDRESS_BAR_ID,
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
            f"The address bar reads {second_page!r}, exactly what was typed.",
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
            step=f"Find {SECOND_PAGE_LABEL} on the page that loaded",
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
            f"The page mentions {SECOND_PAGE_LABEL} in {len(named)} places. The "
            f"smallest is {_placed(smallest, _screen(second))}: text inside a "
            "diagram, readable like any other element.",
            SECOND_PAGE_LABEL,
        )


class NotificationDemos(IdbEndToEndTestCase):
    @documented_demo(
        slug="send-and-clear-a-notification",
        title="Send a push notification without a permission prompt or a running app",
        summary=(
            "Grant an app notification permission directly, so there is no "
            "system prompt to automate, then deliver a push notification to it "
            "while it isn't running and see the system hold it for the app. "
            "Clear the app's delivered notifications afterwards to leave the "
            "simulator clean for whatever runs next."
        ),
    )
    async def test_send_and_clear_a_notification(self) -> None:
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
            f"{NEWS_BUNDLE_ID} can now receive notifications. idb granted the "
            "permission directly, so no prompt appeared.",
            NEWS_BUNDLE_ID,
        )

        before = await self.idb(
            "notification",
            "list",
            NEWS_BUNDLE_ID,
            step="List notifications before delivery",
        )
        held = {identifier for identifier, _ in _retained_notifications(before.text)}
        self.note(
            "The app has no delivered notifications."
            if not held
            else (
                f"The app already has {_notifications(len(held))}, so the new "
                "one can be told apart."
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
                for identifier, title in _retained_notifications(text)
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
            if _retained_notifications(completed.text):
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
        self.assertEqual(_retained_notifications(cleared.text), [])
        self.note(
            "The app has no delivered notifications: clearing removed the new one"
            + (f" and the {_notifications(len(held))} there before." if held else ".")
        )
