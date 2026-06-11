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

  func testOrientationEventEquality() {
    XCTAssertEqual(FBSimulatorHIDEvent.setOrientation(.landscapeLeft), .setOrientation(.landscapeLeft))
  }

  func testOrientationEventInequality() {
    XCTAssertNotEqual(FBSimulatorHIDEvent.setOrientation(.portrait), .setOrientation(.landscapeLeft))
  }

  func testOrientationEventHash() {
    XCTAssertNotEqual(
      FBSimulatorHIDEvent.setOrientation(.portrait).hashValue,
      FBSimulatorHIDEvent.setOrientation(.landscapeLeft).hashValue)
    XCTAssertEqual(
      FBSimulatorHIDEvent.setOrientation(.portrait).hashValue,
      FBSimulatorHIDEvent.setOrientation(.portrait).hashValue)
  }

  func testOrientationEventDescription() {
    let description = FBSimulatorHIDEvent.setOrientation(.landscapeLeft).description
    XCTAssertTrue(description.contains("landscape_left"), "Description should contain orientation name, got: \(description)")
  }

  func testSetOrientationFactory() {
    guard case .deviceOrientation(.portraitUpsideDown) = FBSimulatorHIDEvent.setOrientation(.portraitUpsideDown) else {
      return XCTFail("setOrientation should produce a .deviceOrientation event")
    }
  }

  func testAllOrientationsCreateDistinctEvents() {
    let events: Set<FBSimulatorHIDEvent> = [
      .setOrientation(.portrait),
      .setOrientation(.portraitUpsideDown),
      .setOrientation(.landscapeRight),
      .setOrientation(.landscapeLeft),
    ]
    XCTAssertEqual(events.count, 4, "All four orientations should be distinct")
  }

  // MARK: - Shake

  func testShakeFactory() {
    XCTAssertEqual(FBSimulatorHIDEvent.shake(), .shake)
  }

  func testShakeEquality() {
    XCTAssertEqual(FBSimulatorHIDEvent.shake(), FBSimulatorHIDEvent.shake())
  }

  func testShakeDescription() {
    XCTAssertTrue(FBSimulatorHIDEvent.shake().description.contains("Shake"))
  }

  // MARK: - Lock Device

  func testLockDeviceFactory() {
    XCTAssertEqual(FBSimulatorHIDEvent.lockDevice(), .lockDevice)
  }

  func testLockDeviceDescription() {
    XCTAssertTrue(FBSimulatorHIDEvent.lockDevice().description.contains("Lock"))
  }

  func testLockDeviceEquality() {
    XCTAssertEqual(FBSimulatorHIDEvent.lockDevice(), FBSimulatorHIDEvent.lockDevice())
  }
}
