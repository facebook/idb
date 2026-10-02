/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Testing

@Suite("Hardware keyboard setting")
struct SimulatorPreferencesCommandsTests {

  @Test("Enabling the hardware keyboard writes only the attached state")
  func enable() {
    // BUG: apps keep showing the software keyboard unless the keyboard daemon's automatic
    // minimization preference is also on, which a fresh simulator lacks — flipped in the following commit.
    #expect(SimulatorPreferencesCommands.hardwareKeyboardSteps(enabled: true) == [.write(enabled: true)])
  }

  @Test("Disabling the hardware keyboard writes only the attached state")
  func disable() {
    #expect(SimulatorPreferencesCommands.hardwareKeyboardSteps(enabled: false) == [.write(enabled: false)])
  }
}
