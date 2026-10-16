/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
@testable import FBSimulatorServices
import Foundation
import Testing

@Suite
struct SimulatorOrientationCommandsTests {
  @Test
  func motionStatePreservesPhysicalDirectionsAndFlatStates() throws {
    let orientations: [SimulatorDeviceOrientation] = [.unknown, .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight, .faceUp, .faceDown]
    for (value, orientation) in orientations.enumerated() {
      #expect(try SimulatorOrientationCommands.decodeMotionState("{\"orientation\":\(value)}") == orientation)
    }
  }

  @Test
  func invalidMotionStateDoesNotDefaultToPortrait() {
    for output in ["", "{}", "null", "[]", "{\"orientation\":null}", "{\"orientation\":true}", "{\"orientation\":\"1\"}", "{\"orientation\":1.5}", "{\"orientation\":-1}", "{\"orientation\":7}"] {
      #expect(throws: (any Error).self, "\(output)") { try SimulatorOrientationCommands.decodeMotionState(output) }
    }
  }
}
