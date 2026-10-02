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

import json
import shutil
import struct
import time
import unittest
import zlib
from pathlib import Path
from typing import Any

from .documentation import documented_demo
from .harness import (
    _center,
    _elements,
    _has_area,
    _label,
    _screen,
    Completed,
    FIXTURE_APP_BUNDLE_ID,
    IdbEndToEndTestCase,
    LocalPages,
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
    "test_navigate_a_list_by_accessibility_id": (
        SuiteCapability.ACCESSIBILITY_INTERACTION
    ),
}
WEB_CONTENT_DEMO_CAPABILITIES = {
    "test_read_web_content_in_safari": SuiteCapability.ACCESSIBILITY_INTERACTION,
}
INJECTED_SWIFT_DEMO_CAPABILITIES = {
    "test_drive_an_app_from_injected_swift": SuiteCapability.ACCESSIBILITY_INTERACTION,
}
SPINNING_SAFARI_DEMO_CAPABILITIES = {
    "test_spin_safaris_address_bar": SuiteCapability.ACCESSIBILITY_INTERACTION,
}
SEEDED_LIBRARY_DEMO_CAPABILITIES = {
    "test_seed_photos_and_a_location": SuiteCapability.ACCESSIBILITY_INTERACTION,
}
DISPLAY_SETTINGS_DEMO_CAPABILITIES = {
    "test_one_screen_across_display_settings": SuiteCapability.ACCESSIBILITY_READ,
}
CRASH_REPORT_DEMO_CAPABILITIES = {
    "test_crash_and_read_the_report": SuiteCapability.PROCESS_CONTROL,
}

COUNTER_ID = "injected-counter"
TAPS = 3
# The Swift a demo injects is published as part of its command, so it is
# written to be read there.
ADD_COUNTER = r"""import UIKit
return await MainActor.run { () -> String in
  let window = UIApplication.shared.connectedScenes
    .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
  guard let window else { return "No window to add to" }
  let button = UIButton(configuration: .borderedProminent())
  button.configuration?.title = "Taps: 0"
  button.accessibilityIdentifier = "injected-counter"
  button.addAction(UIAction { action in
    guard let button = action.sender as? UIButton else { return }
    button.tag += 1
    button.configuration?.title = "Taps: \(button.tag)"
  }, for: .primaryActionTriggered)
  button.translatesAutoresizingMaskIntoConstraints = false
  window.addSubview(button)
  NSLayoutConstraint.activate([
    button.centerXAnchor.constraint(equalTo: window.centerXAnchor),
    button.bottomAnchor.constraint(
      equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -48),
  ])
  return "Added a button to \(Bundle.main.bundleIdentifier ?? "the app")"
}"""
READ_COUNTER = r"""import UIKit
return await MainActor.run { () -> String in
  func counter(in view: UIView) -> UIButton? {
    if view.accessibilityIdentifier == "injected-counter" { return view as? UIButton }
    return view.subviews.lazy.compactMap { counter(in: $0) }.first
  }
  let windows = UIApplication.shared.connectedScenes
    .flatMap { ($0 as? UIWindowScene)?.windows ?? [] }
  guard let button = windows.lazy.compactMap({ counter(in: $0) }).first
  else { return "The button is gone" }
  return "The button counted \(button.tag) taps"
}"""
WHO_AM_I = 'return Bundle.main.bundleIdentifier ?? "no bundle"'
SPIN_ADDRESS_BAR = r"""import UIKit
return await MainActor.run { () -> String in
  func addressBar(in view: UIView) -> UIView? {
    if view.accessibilityIdentifier == "TabBarItemTitle" { return view }
    return view.subviews.lazy.compactMap { addressBar(in: $0) }.first
  }
  let windows = UIApplication.shared.connectedScenes
    .flatMap { ($0 as? UIWindowScene)?.windows ?? [] }
  guard let bar = windows.lazy.compactMap({ addressBar(in: $0) }).first
  else { return "No address bar to spin" }
  let spin = CABasicAnimation(keyPath: "transform.rotation.z")
  spin.byValue = 2 * Double.pi
  spin.duration = 1.5
  spin.repeatCount = .infinity
  bar.layer.add(spin, forKey: "idb-spin")
  return "Spinning a \(type(of: bar))"
}"""
STOP_SPINNING = r"""import UIKit
return await MainActor.run { () -> String in
  func spinning(in view: UIView) -> [UIView] {
    let here = view.layer.animation(forKey: "idb-spin") == nil ? [] : [view]
    return here + view.subviews.flatMap { spinning(in: $0) }
  }
  let windows = UIApplication.shared.connectedScenes
    .flatMap { ($0 as? UIWindowScene)?.windows ?? [] }
  let views = windows.flatMap { spinning(in: $0) }
  views.forEach { $0.layer.removeAnimation(forKey: "idb-spin") }
  return "Stopped \(views.count) spinning view(s)"
}"""


LIBRARY_ID = "seeded-library"
PHOTO_SIZE = 64
PHOTOS = {
    "sunrise.png": (255, 149, 0),
    "sea.png": (0, 122, 255),
    "leaf.png": (52, 199, 89),
}
MENLO_PARK = ("37.4848", "-122.1484")
LONDON = ("51.5072", "-0.1276")
ALLOW_LOCATION = "Allow While Using App"
SHOW_LIBRARY = r"""import CoreLocation
import Photos
import UIKit
let options = PHImageRequestOptions()
options.isSynchronous = true
var found: [UIImage] = []
PHAsset.fetchAssets(with: .image, options: nil).enumerateObjects { asset, _, _ in
  PHImageManager.default().requestImage(
    for: asset, targetSize: CGSize(width: 192, height: 192),
    contentMode: .aspectFill, options: options
  ) { image, _ in image.map { found.append($0) } }
}
let photos = found
return await MainActor.run { () -> String in
  let window = UIApplication.shared.connectedScenes
    .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
  guard let window else { return "No window to show them in" }
  let row = UIStackView(arrangedSubviews: photos.map { photo in
    let view = UIImageView(image: photo)
    view.layer.cornerRadius = 16
    view.clipsToBounds = true
    view.widthAnchor.constraint(equalToConstant: 96).isActive = true
    view.heightAnchor.constraint(equalToConstant: 96).isActive = true
    return view
  })
  row.spacing = 12
  let label = UILabel()
  label.accessibilityIdentifier = "seeded-library"
  label.text = "\(photos.count) photos, waiting for a location"
  let column = UIStackView(arrangedSubviews: [row, label])
  column.axis = .vertical
  column.alignment = .center
  column.spacing = 24
  column.backgroundColor = .systemBackground
  column.frame = window.bounds
  column.autoresizingMask = [.flexibleWidth, .flexibleHeight]
  column.isLayoutMarginsRelativeArrangement = true
  window.addSubview(column)
  Task {
    for try await update in CLLocationUpdate.liveUpdates() {
      guard let place = update.location?.coordinate else { continue }
      label.text = String(
        format: "%d photos at %.4f, %.4f",
        photos.count, place.latitude, place.longitude)
    }
  }
  return "Showing \(photos.count) photos, and following the location"
}"""

SETTINGS_ID = "screen-settings"
STARTING_SETTINGS = {
    "appearance": "light",
    "content-size": "large",
    "increase-contrast": "disable",
}
# `idb get` reports increase-contrast as a state, and `idb set` takes a verb.
SET_VALUE_FOR_READ_VALUE = {"enabled": "enable", "disabled": "disable"}
SHOW_SETTINGS = r"""import UIKit
return await MainActor.run { () -> String in
  let window = UIApplication.shared.connectedScenes
    .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
  guard let window else { return "No window to show it in" }
  func settings(of traits: UITraitCollection) -> String {
    let appearance = traits.userInterfaceStyle == .dark ? "dark" : "light"
    let size = [
      UIContentSizeCategory.large: "large",
      .accessibilityExtraLarge: "accessibility-extra-large",
    ][traits.preferredContentSizeCategory]
      ?? traits.preferredContentSizeCategory.rawValue
    let contrast = traits.accessibilityContrast == .high ? "high" : "standard"
    return "\(appearance), \(size), \(contrast) contrast"
  }
  let label = UILabel()
  label.accessibilityIdentifier = "screen-settings"
  label.font = .preferredFont(forTextStyle: .title1)
  label.adjustsFontForContentSizeCategory = true
  label.numberOfLines = 0
  label.textAlignment = .center
  let swatches = UIStackView(arrangedSubviews: [
    UIColor.systemRed, .systemOrange, .systemGreen, .systemBlue,
  ].map { colour in
    let swatch = UIView()
    swatch.backgroundColor = colour
    swatch.layer.cornerRadius = 24
    swatch.widthAnchor.constraint(equalToConstant: 48).isActive = true
    swatch.heightAnchor.constraint(equalToConstant: 48).isActive = true
    return swatch
  })
  swatches.spacing = 12
  let column = UIStackView(arrangedSubviews: [swatches, label])
  column.axis = .vertical
  column.alignment = .center
  column.spacing = 24
  column.translatesAutoresizingMaskIntoConstraints = false
  let screen = UIView(frame: window.bounds)
  screen.backgroundColor = .systemBackground
  screen.autoresizingMask = [.flexibleWidth, .flexibleHeight]
  screen.addSubview(column)
  NSLayoutConstraint.activate([
    column.centerXAnchor.constraint(equalTo: screen.centerXAnchor),
    column.centerYAnchor.constraint(equalTo: screen.centerYAnchor),
    label.widthAnchor.constraint(lessThanOrEqualTo: screen.widthAnchor, constant: -48),
  ])
  window.addSubview(screen)
  label.text = settings(of: screen.traitCollection)
  let traits: [UITrait] = [
    UITraitUserInterfaceStyle.self,
    UITraitPreferredContentSizeCategory.self,
    UITraitAccessibilityContrast.self,
  ]
  screen.registerForTraitChanges(traits) { (screen: UIView, _: UITraitCollection) in
    label.text = settings(of: screen.traitCollection)
  }
  return "Showing \(label.text ?? "nothing")"
}"""

CRASH_SCHEDULED = "ReplHost will crash in a second"
# The Swift returns before the crash it schedules, so idb-repl prints a result
# rather than losing its connection to the app mid-run.
CRASH_LATER = f"""import Foundation
DispatchQueue.main.asyncAfter(deadline: .now() + 1) {{
  fatalError("Crashed on purpose by Swift that idb-repl injected")
}}
return "{CRASH_SCHEDULED}"
"""
# A report records the crashing thread's frames but not the fatalError message.
# idb-repl wraps a session's first run in userCode_0, so the scheduled closure is
# the first closure in it.
CRASH_FRAME = "closure #1 in userCode_0()"
CRASH_REPORT_TIMEOUT_SECONDS = 60.0


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
                    (InjectedSwiftDemos, INJECTED_SWIFT_DEMO_CAPABILITIES),
                    (SpinningSafariDemos, SPINNING_SAFARI_DEMO_CAPABILITIES),
                    (SeededLibraryDemos, SEEDED_LIBRARY_DEMO_CAPABILITIES),
                    (DisplaySettingsDemos, DISPLAY_SETTINGS_DEMO_CAPABILITIES),
                    (CrashReportDemos, CRASH_REPORT_DEMO_CAPABILITIES),
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
        slug="navigate-a-list-by-accessibility-id",
        title="Scroll a list and open a row by accessibility identifier",
        summary=(
            "Scroll a list down from its General row and back up from a row "
            "that scrolled into view, then tap General to open its page, "
            "naming every element by its accessibility identifier. idb "
            "performs the platform's page-scroll action on the list that "
            "contains the element and activates the row directly, so there "
            "are no screen coordinates, swipe velocities or inertial "
            "deceleration to account for. Reading the accessibility tree "
            "before and after each scroll shows how far every row moved."
        ),
    )
    async def test_navigate_a_list_by_accessibility_id(self) -> None:
        await self.scroll_down_and_back()
        await self.open_general()

    async def open_general(self) -> None:
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

    async def scroll_down_and_back(self) -> None:
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
        # has to open it from the home screen. Terminating Safari is what
        # returns there: SpringBoard holds a home button press until a second
        # press can no longer follow it, so one sent here can act after the
        # recorded `idb open` and put Safari back behind the home screen.
        await self.setup_terminate_quietly(SAFARI_BUNDLE_ID)
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


def _result(completed: Completed) -> str:
    """What injected Swift returned, from idb-repl's `Result:` block."""
    _, marker, result = completed.text.partition("Result:\n")
    if not marker:
        raise AssertionError(f"idb-repl printed no result: {completed.text!r}")
    return result.strip()


class InjectedSwiftCase(IdbEndToEndTestCase):
    """Reads back the views a demo's injected Swift added to an app."""

    async def describe_one(self, identifier: str, *, step: str) -> dict[str, Any]:
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
        found = _visible(document, identifier)
        self.assertEqual(len(found), 1, f"Expected one {identifier}: {document}")
        return found[0]

    async def wait_for_label(self, label: str) -> None:
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


class InjectedSwiftDemos(InjectedSwiftCase):
    capabilities = INJECTED_SWIFT_DEMO_CAPABILITIES

    @documented_demo(
        slug="drive-an-app-from-injected-swift",
        title="Add a control to a running app with injected Swift, then drive it",
        summary=(
            "Compile a few lines of Swift on the host and run them inside a "
            "running app, adding a button the app was never built with. idb "
            "finds the new button in the accessibility tree like any other "
            "control and taps it. Its label counts the taps, and asking the "
            "same live process how many it counted gives the same answer."
        ),
    )
    async def test_drive_an_app_from_injected_swift(self) -> None:
        self.addAsyncCleanup(self.setup_terminate_quietly, FIXTURE_APP_BUNDLE_ID)
        await self.setup_terminate_quietly(FIXTURE_APP_BUNDLE_ID)

        added = await self.idb_repl(
            "app",
            "--new-session",
            ADD_COUNTER,
            step="Add a button to a running app with injected Swift",
        )
        self.assertEqual(_result(added), f"Added a button to {FIXTURE_APP_BUNDLE_ID}")
        self.note(
            "idb-repl launched the host app with the REPL injected, compiled the "
            "Swift on the host and ran it inside the app. The button is plain "
            "UIKit, added while the app runs.",
            FIXTURE_APP_BUNDLE_ID,
        )

        await self.wait_for_label("Taps: 0")
        counter = await self.describe_one(
            COUNTER_ID, step="Find the new button by its accessibility identifier"
        )
        self.assertEqual(_label(counter), "Taps: 0")
        self.note(
            f"The button is a {counter.get('type')} labelled 'Taps: 0', "
            f"{_placed(counter, None)}. idb reads it like any control the app "
            "shipped with.",
            COUNTER_ID,
            "Taps: 0",
        )

        for tap in range(1, TAPS + 1):
            await self.idb(
                "ui",
                "tap",
                COUNTER_ID,
                "--match-key",
                "AXUniqueId",
                step=f"Tap the new button ({tap} of {TAPS})",
            )
            await self.wait_for_label(f"Taps: {tap}")

        counted = await self.describe_one(
            COUNTER_ID, step=f"Read the button's label after {TAPS} taps"
        )
        self.assertEqual(_label(counted), f"Taps: {TAPS}")
        self.note(
            f"The label reads 'Taps: {TAPS}': each tap ran the action the "
            "injected Swift attached.",
            f"Taps: {TAPS}",
        )

        read = await self.idb_repl(
            "app",
            READ_COUNTER,
            step="Ask the running app how many taps it counted",
        )
        self.assertEqual(_result(read), f"The button counted {TAPS} taps")
        self.note(
            "idb-repl attached to the same process rather than relaunching it, "
            f"so the button and its count of {TAPS} were still there.",
            f"{TAPS} taps",
        )


class SpinningSafariDemos(SafariTestCase):
    capabilities = SPINNING_SAFARI_DEMO_CAPABILITIES

    async def describe_address_bar(self, *, step: str) -> dict[str, Any]:
        document = await self.idb_json(
            "ui",
            "describe",
            SAFARI_ADDRESS_BAR_ID,
            "--match-key",
            "AXUniqueId",
            "--api",
            "axbridge",
            "--format",
            "complete",
            step=step,
        )
        bars = _visible(document, SAFARI_ADDRESS_BAR_ID)
        self.assertEqual(len(bars), 1, f"Expected one address bar: {document}")
        return bars[0]

    @documented_demo(
        slug="spin-safaris-address-bar",
        title="Spin Safari's address bar, and tap it anyway",
        summary=(
            "Inject Swift into Safari, one of Apple's own apps, and set its "
            "address bar spinning with Core Animation. The spin only changes "
            "what is drawn, so the accessibility tree still reports the bar "
            "exactly where it was, and idb taps it mid-spin. Then stop it."
        ),
    )
    async def test_spin_safaris_address_bar(self) -> None:
        pages = LocalPages({FIRST_PAGE_PATH: STAND_IN_PAGES[FIRST_PAGE_PATH]})
        origin = pages.start()
        self.addCleanup(pages.stop)

        launched = await self.idb_repl(
            "app",
            "--bundle-id",
            SAFARI_BUNDLE_ID,
            "--new-session",
            WHO_AM_I,
            step="Launch Safari with Swift injected, and ask who it is",
        )
        self.assertEqual(_result(launched), SAFARI_BUNDLE_ID)
        self.note(
            f"The Swift ran inside Safari, which answers {SAFARI_BUNDLE_ID}. "
            "Nothing about Safari was rebuilt or re-signed.",
            SAFARI_BUNDLE_ID,
        )

        await self.idb(
            "open", origin + FIRST_PAGE_PATH, step="Open a page in the same Safari"
        )
        await self.wait_for_web_label(FIRST_PAGE_HEADING)
        await self.wait_for_tappable_address_bar()
        before = await self.describe_address_bar(step="Find the address bar")
        self.note(
            f"The address bar has accessibility identifier "
            f"{SAFARI_ADDRESS_BAR_ID} and is {_placed(before, None)}.",
            SAFARI_ADDRESS_BAR_ID,
        )

        spun = await self.idb_repl(
            "app",
            "--bundle-id",
            SAFARI_BUNDLE_ID,
            SPIN_ADDRESS_BAR,
            step="Set the address bar spinning",
        )
        spinning = _result(spun)
        self.assertTrue(spinning.startswith("Spinning a "), spinning)
        self.note(
            "The Swift found the view behind the address bar and added a "
            "rotation that repeats forever.",
            spinning,
        )

        during = await self.describe_address_bar(
            step="Find the address bar while it spins"
        )
        self.assertEqual(during["frame"], before["frame"])
        self.note(
            f"It is still {_placed(during, None)}. Core Animation spins what "
            "is drawn, not where UIKit lays the view out, and the "
            "accessibility tree reports the layout.",
            SAFARI_ADDRESS_BAR_ID,
        )

        await self.idb(
            "ui",
            "tap",
            SAFARI_ADDRESS_BAR_ID,
            "--match-key",
            "AXUniqueId",
            step="Tap the spinning address bar",
        )
        await self.wait_for_address_bar()
        self.note(
            "The tap landed where the bar is laid out, and Safari gave the "
            "address field the cursor.",
            SAFARI_ADDRESS_BAR_ID,
        )

        stopped = await self.idb_repl(
            "app",
            "--bundle-id",
            SAFARI_BUNDLE_ID,
            STOP_SPINNING,
            step="Stop the spin",
        )
        self.assertTrue(_result(stopped).startswith("Stopped "), stopped.text)
        self.note(
            "idb-repl attached to the Safari it launched, found whatever was "
            "still spinning and removed the animation.",
            _result(stopped),
        )


def _png(colour: tuple[int, int, int]) -> bytes:
    """A square PNG of one colour, so each seeded photo is told apart by eye."""

    def chunk(kind: bytes, data: bytes) -> bytes:
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    row = b"\x00" + bytes(colour) * PHOTO_SIZE
    return b"".join(
        [
            b"\x89PNG\r\n\x1a\n",
            chunk(
                b"IHDR", struct.pack(">IIBBBBB", PHOTO_SIZE, PHOTO_SIZE, 8, 2, 0, 0, 0)
            ),
            chunk(b"IDAT", zlib.compress(row * PHOTO_SIZE)),
            chunk(b"IEND", b""),
        ]
    )


class SeededLibraryDemos(InjectedSwiftCase):
    capabilities = SEEDED_LIBRARY_DEMO_CAPABILITIES

    def write_photos(self) -> list[Path]:
        # Inside the companion's directory, so the published paths read the
        # same on every run.
        directory = self.companion.directory / "seeded-photos"
        directory.mkdir(exist_ok=True)
        self.addCleanup(shutil.rmtree, directory, ignore_errors=True)
        paths = []
        for name, colour in PHOTOS.items():
            path = directory / name
            path.write_bytes(_png(colour))
            paths.append(path)
        return paths

    async def wait_for_place(self, place: tuple[str, str]) -> str:
        label = f"{len(PHOTOS)} photos at {place[0]}, {place[1]}"
        await self.wait_for_label(label)
        return label

    @documented_demo(
        slug="seed-photos-and-a-location",
        title="Seed photos and a location, and watch an app pick them up",
        summary=(
            "Give a simulator a known photo library and location: clear its "
            "photos, add three, let an app read them, and put the simulator in "
            "Menlo Park. Swift injected into the app shows the photos and asks "
            "for the location, idb answers the system prompt, and when idb "
            "moves the simulator to London the app follows it there."
        ),
    )
    async def test_seed_photos_and_a_location(self) -> None:
        photos = self.write_photos()
        # The library and location are cleared rather than restored: no test
        # relies on the simulator's sample photos or where it is.
        self.addAsyncCleanup(self.setup_idb, "photos", "clear")
        self.addAsyncCleanup(self.simctl.run, "location", self.udid, "clear")
        self.addAsyncCleanup(
            self.idb, "revoke", FIXTURE_APP_BUNDLE_ID, "photos", "location", check=False
        )
        self.addAsyncCleanup(self.setup_terminate_quietly, FIXTURE_APP_BUNDLE_ID)
        await self.setup_terminate_quietly(FIXTURE_APP_BUNDLE_ID)

        await self.idb("photos", "clear", step="Start from an empty photo library")
        self.note("The simulator's sample photos are gone.")

        await self.idb(
            "add-media", *(str(path) for path in photos), step="Add three photos"
        )
        self.note(
            "Three one-colour images, written by the test, are now the whole "
            "photo library."
        )

        await self.idb(
            "approve",
            FIXTURE_APP_BUNDLE_ID,
            "photos",
            step="Let the app read photos",
        )
        self.note("Granted ahead of time, so the app never asks for the photos.")

        await self.idb(
            "set-location", *MENLO_PARK, step="Put the simulator in Menlo Park"
        )

        shown = await self.idb_repl(
            "app",
            "--new-session",
            SHOW_LIBRARY,
            step="Show the photos and follow the location, with injected Swift",
        )
        self.assertEqual(
            _result(shown),
            f"Showing {len(PHOTOS)} photos, and following the location",
        )
        self.note(
            f"The injected Swift read {len(PHOTOS)} photos from the library, "
            "put them on screen, and left a task running in the app that "
            "follows the location.",
            f"{len(PHOTOS)} photos",
        )

        await self.wait_for_label(ALLOW_LOCATION)
        await self.idb("ui", "tap", ALLOW_LOCATION, step="Answer the location prompt")
        self.note(
            "The app asked to use the location, and idb pressed the button on "
            "the system's prompt by its label."
        )

        in_menlo_park = await self.wait_for_place(MENLO_PARK)
        library = await self.describe_one(LIBRARY_ID, step="Read what the app shows")
        self.assertEqual(_label(library), in_menlo_park)
        self.note(
            f"The app reads '{in_menlo_park}': the photos idb added and the "
            "location idb set.",
            in_menlo_park,
        )

        await self.idb("set-location", *LONDON, step="Move the simulator to London")

        in_london = await self.wait_for_place(LONDON)
        moved = await self.describe_one(LIBRARY_ID, step="Read what the app shows now")
        self.assertEqual(_label(moved), in_london)
        self.note(
            f"The app now reads '{in_london}'. Nothing was relaunched: the "
            "task the Swift left running saw the location change.",
            in_london,
        )


class DisplaySettingsDemos(InjectedSwiftCase):
    async def restore_settings_afterwards(self) -> None:
        for name in STARTING_SETTINGS:
            current = (await self.setup_idb("get", name)).text.strip()
            self.addAsyncCleanup(
                self.setup_idb,
                "set",
                name,
                SET_VALUE_FOR_READ_VALUE.get(current, current),
            )

    async def read_settings(self, expected: str, *, step: str) -> dict[str, Any]:
        await self.wait_for_label(expected)
        screen = await self.describe_one(SETTINGS_ID, step=step)
        self.assertEqual(_label(screen), expected)
        return screen

    @documented_demo(
        slug="one-screen-across-display-settings",
        title="Check one screen in dark mode, at a large text size, and with more contrast",
        summary=(
            "Swift injected into an app shows a screen that reports the "
            "appearance, text size and contrast it is drawn with. idb switches "
            "the simulator to dark mode, turns the text size up and increases "
            "contrast, one at a time, and reads the screen after each change "
            "while the app keeps running."
        ),
    )
    async def test_one_screen_across_display_settings(self) -> None:
        await self.restore_settings_afterwards()
        self.addAsyncCleanup(self.setup_terminate_quietly, FIXTURE_APP_BUNDLE_ID)
        for name, value in STARTING_SETTINGS.items():
            await self.setup_idb("set", name, value)
        await self.setup_terminate_quietly(FIXTURE_APP_BUNDLE_ID)

        standard = "light, large, standard contrast"
        shown = await self.idb_repl(
            "app",
            "--new-session",
            SHOW_SETTINGS,
            step="Show a screen that reports its own settings, with injected Swift",
        )
        self.assertEqual(_result(shown), f"Showing {standard}")
        self.note(
            "The screen reads the appearance, text size and contrast from its "
            "trait collection, and rereads them whenever one changes.",
            standard,
        )

        await self.idb("set", "appearance", "dark", step="Switch to dark mode")
        dark = "dark, large, standard contrast"
        before = await self.read_settings(dark, step="Read the screen in dark mode")
        self.note(f"The running app redrew itself for dark mode: '{dark}'.", dark)

        await self.idb(
            "set",
            "content-size",
            "accessibility-extra-large",
            step="Turn the text size up",
        )
        larger = "dark, accessibility-extra-large, standard contrast"
        after = await self.read_settings(larger, step="Read the screen at that size")
        grown_from = before["frame"]["height"]
        grown_to = after["frame"]["height"]
        self.assertGreater(grown_to, grown_from)
        self.note(
            f"The label is now {grown_to:.0f} points tall, up from "
            f"{grown_from:.0f}: its font followed the text size.",
            larger,
        )

        await self.idb("set", "increase-contrast", "enable", step="Increase contrast")
        contrast = "dark, accessibility-extra-large, high contrast"
        await self.read_settings(contrast, step="Read the screen with more contrast")
        self.note("All three settings changed without relaunching the app.", contrast)

        read_back = await self.idb(
            "get", "content-size", step="Read a setting back from the simulator"
        )
        self.assertEqual(read_back.text.strip(), "accessibility-extra-large")
        self.note(
            "idb reads settings as well as setting them, which is how the test "
            "puts back what it found.",
            "accessibility-extra-large",
        )


def _crash_names(completed: Completed) -> list[str]:
    return [
        json.loads(line)["name"] for line in completed.text.splitlines() if line.strip()
    ]


class CrashReportDemos(IdbEndToEndTestCase):
    capabilities = CRASH_REPORT_DEMO_CAPABILITIES

    @documented_demo(
        slug="crash-and-read-the-report",
        title="Crash an app on purpose and read its crash report",
        summary=(
            "Swift injected into an app schedules a fatal error and returns. Once "
            "the app has crashed, idb lists the crash report the simulator wrote, "
            "shows the report, and deletes it."
        ),
    )
    async def test_crash_and_read_the_report(self) -> None:
        self.addAsyncCleanup(self.setup_terminate_quietly, FIXTURE_APP_BUNDLE_ID)
        await self.setup_idb("crash", "delete", "--bundle-id", FIXTURE_APP_BUNDLE_ID)
        # Whole seconds, and one early, since a report's time is compared to it.
        since = str(int(time.time()) - 1)

        scheduled = await self.idb_repl(
            "app",
            "--new-session",
            CRASH_LATER,
            step="Schedule a crash with injected Swift",
        )
        self.assertEqual(_result(scheduled), CRASH_SCHEDULED)
        self.note(
            "The Swift returned before the crash it scheduled, so idb-repl printed "
            "its result and exited normally.",
            CRASH_SCHEDULED,
        )

        async def reported() -> str:
            completed = await self.setup_idb(
                "crash", "list", "--bundle-id", FIXTURE_APP_BUNDLE_ID, "--since", since
            )
            names = _crash_names(completed)
            if not names:
                raise NotReady(f"no crash report for {FIXTURE_APP_BUNDLE_ID} yet")
            return names[0]

        name = await wait_until(
            f"The simulator wrote no crash report for {FIXTURE_APP_BUNDLE_ID}",
            CRASH_REPORT_TIMEOUT_SECONDS,
            reported,
        )
        self.addAsyncCleanup(self.setup_idb, "crash", "delete", name)

        listed = await self.idb(
            "crash",
            "list",
            "--bundle-id",
            FIXTURE_APP_BUNDLE_ID,
            step="List the app's crash reports",
        )
        self.assertIn(name, _crash_names(listed))
        self.note(
            f"The simulator wrote a crash report for {FIXTURE_APP_BUNDLE_ID}, and idb "
            "lists it with the process that crashed and when.",
            FIXTURE_APP_BUNDLE_ID,
        )

        report = await self.idb("crash", "show", name, step="Read the crash report")
        self.assertIn(CRASH_FRAME, report.text)
        self.assertIn("EXC_BREAKPOINT", report.text)
        self.note(
            "The crashed thread stopped in the closure the injected Swift "
            "scheduled, on the breakpoint trap fatalError raises.",
            CRASH_FRAME,
            "EXC_BREAKPOINT",
        )

        deleted = await self.idb(
            "crash", "delete", name, step="Delete the crash report"
        )
        self.assertEqual(_crash_names(deleted), [name])
        remaining = await self.setup_idb(
            "crash", "list", "--bundle-id", FIXTURE_APP_BUNDLE_ID
        )
        self.assertNotIn(name, _crash_names(remaining))
        self.note("idb no longer lists the report it deleted.")
