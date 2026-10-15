/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import Testing

@Suite
struct SimulatorSetErrorTests {

  @Test
  func shutdownAfterCreateComposesReason() {
    #expect(
      SimulatorSetError.shutdownAfterCreateFailed(reason: "timed out").errorDescription == "Could not get newly-created simulator into a shutdown state: timed out"
    )
    #expect(
      SimulatorSetError.shutdownAfterCreateFailed(reason: nil).errorDescription == "Could not get newly-created simulator into a shutdown state"
    )
  }

  @Test
  func deletionTimeoutDescribesItself() {
    #expect(SimulatorSetError.removalTimedOut.errorDescription == "Timed out waiting for Simulator to be removed from set")
    #expect(String(describing: SimulatorSetError.removalTimedOut) == "Timed out waiting for Simulator to be removed from set")
  }
}
