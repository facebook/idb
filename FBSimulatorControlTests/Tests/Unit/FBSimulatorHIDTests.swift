/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class FBSimulatorHIDTests: XCTestCase {

  // MARK: API surface

  func testSendPurpleEventConvenienceWrapperExists() {
    XCTAssertTrue(
      FBSimulatorHID.instancesRespond(to: NSSelectorFromString("sendPurpleEvent:error:")),
      "Convenience wrapper without timeout must remain available for callers that opt into the default behavior.")
  }

  func testSendPurpleEventWithTimeoutMsExists() {
    XCTAssertTrue(
      FBSimulatorHID.instancesRespond(to: NSSelectorFromString("sendPurpleEvent:timeoutMs:error:")),
      "Timeout-aware overload must be exposed for callers that need to bound the send.")
  }
}
