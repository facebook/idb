/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class FBSimulatorSetErrorTests: XCTestCase {

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
