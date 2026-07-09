/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class FBSimulatorSetErrorTests: XCTestCase {

  func testMessagesAreStable() {
    XCTAssertEqual(
      FBSimulatorSetError.simulatorNotInflated(udid: "ABC-123").errorDescription,
      "Expected simulator with UDID ABC-123 to be inflated"
    )
    XCTAssertEqual(
      FBSimulatorSetError.deviceCreationFailed.errorDescription,
      "Failed to create device with no error"
    )
    XCTAssertEqual(
      FBSimulatorSetError.deviceCloneFailed.errorDescription,
      "Failed to clone device with no error"
    )
  }

  func testShutdownAfterCreateComposesReason() {
    XCTAssertEqual(
      FBSimulatorSetError.shutdownAfterCreateFailed(reason: "timed out").errorDescription,
      "Could not get newly-created simulator into a shutdown state: timed out"
    )
    XCTAssertEqual(
      FBSimulatorSetError.shutdownAfterCreateFailed(reason: nil).errorDescription,
      "Could not get newly-created simulator into a shutdown state"
    )
  }
}
