/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import Testing

/// Coverage of the Siri Remote focus events: the press expands to a `.remoteButton` down/up pair, and
/// the keyboard usage each action carries.
@Suite
struct SimulatorHIDRemoteButtonTests {

  @Test
  func remoteButtonIsAShortRemotePress() {
    for button in SimulatorHIDRemoteButton.allCases {
      #expect(
        SimulatorHIDEvent.remoteButton(button)
          == .composite([
            .remoteButton(direction: .down, button: button),
            .remoteButton(direction: .up, button: button),
          ]),
        "remoteButton(\(button.name)) should be a short press of that remote action")
    }
  }

  @Test
  func remoteButtonKeyboardUsages() {
    let expected: [(SimulatorHIDRemoteButton, UInt32)] = [
      (.up, 0x52),
      (.down, 0x51),
      (.left, 0x50),
      (.right, 0x4F),
      (.select, 0x28), // Return
      (.menu, 0x29), // Escape
    ]
    for (button, keyCode) in expected {
      #expect(
        button.keyboardUsage == keyCode, "\(button.name) should carry keyboard usage \(keyCode)")
    }
  }

  @Test
  func remoteButtonNames() {
    #expect(
      SimulatorHIDRemoteButton.allCases.map(\.name) == ["up", "down", "left", "right", "select", "menu"])
  }
}
