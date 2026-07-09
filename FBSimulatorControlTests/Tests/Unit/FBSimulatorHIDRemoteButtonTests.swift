/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
// Matches the existing XCTest-based FBSimulatorControl unit suite (FBSimulatorIndigoHIDTests et al.).
// ast-grep-ignore: swift-testing/swift/no-new-xctest
import XCTest

/// Coverage of the keyboard-backed Siri Remote focus events. tvOS has no touchscreen; the focus
/// engine is driven via USB HID keyboard usages, so each remote action must lower to a short key
/// press of the expected keycode.
final class FBSimulatorHIDRemoteButtonTests: XCTestCase {

  func testRemoteButtonLowersToKeyboardUsage() {
    let expected: [(FBSimulatorHIDRemoteButton, UInt32)] = [
      (.up, 0x52),
      (.down, 0x51),
      (.left, 0x50),
      (.right, 0x4F),
      (.select, 0x28), // Return
      (.menu, 0x29), // Escape
    ]
    for (button, keyCode) in expected {
      XCTAssertEqual(
        FBSimulatorHIDEvent.remoteButton(button),
        .composite([
          .keyboard(direction: .down, keyCode: keyCode),
          .keyboard(direction: .up, keyCode: keyCode),
        ]),
        "remoteButton(\(button.name)) should be a short key press of \(keyCode)")
    }
  }

  func testRemoteButtonNames() {
    XCTAssertEqual(
      FBSimulatorHIDRemoteButton.allCases.map(\.name),
      ["up", "down", "left", "right", "select", "menu"])
  }
}
