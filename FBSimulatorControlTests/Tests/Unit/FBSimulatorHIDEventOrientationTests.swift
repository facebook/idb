/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class FBSimulatorHIDEventOrientationTests: XCTestCase {

  private func makeEvent(_ orientation: FBSimulatorHIDDeviceOrientation) -> NSObject {
    return FBSimulatorHIDEvent.setOrientation(orientation) as! NSObject
  }

  func testOrientationEventEquality() {
    XCTAssertEqual(makeEvent(.landscapeLeft), makeEvent(.landscapeLeft))
  }

  func testOrientationEventInequality() {
    XCTAssertNotEqual(makeEvent(.portrait), makeEvent(.landscapeLeft))
  }

  func testOrientationEventCopying() {
    let event = makeEvent(.portrait)
    let copy = event.copy() as AnyObject
    XCTAssertTrue(event === copy, "Immutable event should return self from copy")
  }

  func testOrientationEventHash() {
    XCTAssertNotEqual(makeEvent(.portrait).hash, makeEvent(.landscapeLeft).hash)
    XCTAssertEqual(makeEvent(.portrait).hash, makeEvent(.portrait).hash)
  }

  func testOrientationEventDescription() {
    let description = makeEvent(.landscapeLeft).description
    XCTAssertTrue(description.contains("landscape_left"), "Description should contain orientation name, got: \(description)")
  }

  func testSetOrientationFactory() {
    let event: any FBSimulatorHIDEventPayload = FBSimulatorHIDEvent.setOrientation(.portraitUpsideDown)
    XCTAssertNotNil(event)
    XCTAssertTrue((event as AnyObject).conforms(to: FBSimulatorHIDEventProtocol.self))
    XCTAssertTrue((event as AnyObject).conforms(to: FBSimulatorHIDEventPayload.self))
  }

  func testAllOrientationsCreateDistinctEvents() {
    let events: [NSObject] = [
      makeEvent(.portrait),
      makeEvent(.portraitUpsideDown),
      makeEvent(.landscapeRight),
      makeEvent(.landscapeLeft),
    ]
    let unique = Set(events)
    XCTAssertEqual(unique.count, 4, "All four orientations should be distinct")
  }

  // MARK: - Shake

  func testShakeFactory() {
    let event: any FBSimulatorHIDEventPayload = FBSimulatorHIDEvent.shake()
    XCTAssertNotNil(event)
    XCTAssertTrue((event as AnyObject).conforms(to: FBSimulatorHIDEventProtocol.self))
    XCTAssertTrue((event as AnyObject).conforms(to: FBSimulatorHIDEventPayload.self))
  }

  func testShakeEquality() {
    let event1 = FBSimulatorHIDEvent.shake() as! NSObject
    let event2 = FBSimulatorHIDEvent.shake() as! NSObject
    XCTAssertEqual(event1, event2)
  }

  func testShakeCopying() {
    let event = FBSimulatorHIDEvent.shake() as AnyObject
    let copy = (event as! NSObject).copy() as AnyObject
    XCTAssertTrue(event === copy, "Immutable event should return self from copy")
  }

  func testShakeDescription() {
    let event = FBSimulatorHIDEvent.shake() as! NSObject
    XCTAssertTrue(event.description.contains("Shake"))
  }

  // MARK: - Lock Device

  func testLockDeviceFactory() {
    let event = FBSimulatorHIDEvent.lockDevice()
    XCTAssertNotNil(event)
  }

  func testLockDeviceDescription() {
    let event = FBSimulatorHIDEvent.lockDevice() as! NSObject
    XCTAssertTrue(event.description.contains("Lock"))
  }

  func testLockDeviceEquality() {
    let event1 = FBSimulatorHIDEvent.lockDevice() as! NSObject
    let event2 = FBSimulatorHIDEvent.lockDevice() as! NSObject
    XCTAssertEqual(event1, event2)
  }

  func testLockDeviceCopying() {
    let event = FBSimulatorHIDEvent.lockDevice() as! NSObject
    let copied = event.copy() as! NSObject
    XCTAssertEqual(event, copied)
  }
}
