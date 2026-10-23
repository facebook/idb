/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
@testable import FBSimulatorServices
import Foundation
import Testing

@Suite("Simulator lock screen commands")
struct SimulatorLockScreenCommandsTests {
  @Test("The guest's lock state decodes from its one JSON value")
  func decodesTheGuestsLockState() throws {
    let state = try SimulatorLockState.decode(bridgeOutput: #"{"locked":true}"# + "\n")
    #expect(state.locked)
  }

  @Test("Output that is not a lock state fails with what the guest printed")
  func rejectsOutputThatIsNotALockState() {
    #expect {
      try SimulatorLockState.decode(bridgeOutput: #"{"locked":"yes"}"#)
    } throws: { error in
      guard case let .undecodableState(output, _) = error as? SimulatorLockScreenError else { return false }
      return output == #"{"locked":"yes"}"#
    }
  }

  @Test("Each command names its lock screen action in failures")
  func commandsNameTheirAction() {
    #expect(BridgeCommand.lockScreen(.state).serviceAndAction == "lock-screen state")
    #expect(BridgeCommand.lockScreen(.lock).serviceAndAction == "lock-screen lock")
    #expect(BridgeCommand.lockScreen(.unlock).serviceAndAction == "lock-screen unlock")
  }
}
