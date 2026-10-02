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

  @Test("Enabling the hardware keyboard turns on automatic minimization before writing the attached state")
  func enable() {
    #expect(
      SimulatorPreferencesCommands.hardwareKeyboardSteps(enabled: true) == [
        .enableAutomaticMinimization, .write(enabled: true),
      ])
  }

  @Test("Disabling the hardware keyboard writes only the attached state")
  func disable() {
    #expect(SimulatorPreferencesCommands.hardwareKeyboardSteps(enabled: false) == [.write(enabled: false)])
  }
}
