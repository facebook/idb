/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class FBSimulatorHIDEventOrientationTests: XCTestCase {

  // MARK: - Orientation

  func testOrientationEventDescription() {
    let description = FBSimulatorHIDEvent.deviceOrientation(.landscapeLeft).description
    XCTAssertTrue(description.contains("landscape_left"), "Description should contain orientation name, got: \(description)")
  }

  // MARK: - Shake

  func testShakeDescription() {
    XCTAssertTrue(FBSimulatorHIDEvent.shake.description.contains("Shake"))
  }

  // MARK: - Lock Device

  func testLockDeviceDescription() {
    XCTAssertTrue(FBSimulatorHIDEvent.lockDevice.description.contains("Lock"))
  }
}
