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
    #expect(SimulatorDeletionError.removalTimedOut.errorDescription == "Timed out waiting for Simulator to be removed from set")
    // BUG: interpolating the error shows only its case name, unlike the set's other errors — flipped in the following commit.
    #expect(String(describing: SimulatorDeletionError.removalTimedOut) == "removalTimedOut")
  }
}
