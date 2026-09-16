/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Carbon
@testable import FBSimulatorControl
import Foundation
import XCTest

final class SimulatorControlValueTypeTests: XCTestCase {

  func testHIDEvents() {
    let events: [SimulatorHIDEvent] = [
      .tapAt(x: 10, y: 20),
      .shortButtonPress(.applePay),
      .shortButtonPress(.homeButton),
      .shortButtonPress(.lock),
      .shortButtonPress(.sideButton),
      .shortButtonPress(.siri),
      .shortKeyPress(UInt32(kVK_ANSI_W)),
      .shortKeyPress(UInt32(kVK_ANSI_A)),
      .shortKeyPress(UInt32(kVK_ANSI_R)),
      .shortKeyPress(UInt32(kVK_ANSI_I)),
      .shortKeyPress(UInt32(kVK_ANSI_O)),
    ]
    let copies: [SimulatorHIDEvent] = [
      .tapAt(x: 10, y: 20),
      .shortButtonPress(.applePay),
      .shortButtonPress(.homeButton),
      .shortButtonPress(.lock),
      .shortButtonPress(.sideButton),
      .shortButtonPress(.siri),
      .shortKeyPress(UInt32(kVK_ANSI_W)),
      .shortKeyPress(UInt32(kVK_ANSI_A)),
      .shortKeyPress(UInt32(kVK_ANSI_R)),
      .shortKeyPress(UInt32(kVK_ANSI_I)),
      .shortKeyPress(UInt32(kVK_ANSI_O)),
    ]
    for (event, copy) in zip(events, copies) {
      XCTAssertEqual(event, copy)
      XCTAssertEqual(event.hashValue, copy.hashValue)
    }
  }

  func testDeliveredNotificationsFailOnALineTheyCannotDecode() throws {
    let record = #"{"bundleID":"com.foo","identifier":"one","title":"T","subtitle":"S","body":"B","threadIdentifier":"th","date":1}"#

    XCTAssertEqual(try DeliveredNotification.records(fromBridgeOutput: "\(record)\n\(record)").count, 2)

    // Both halves of what the guest can break: a line that is not JSON at all, and one that
    // is but does not carry a whole record. Passing over either answers with a list shorter
    // than the app's, which reads as an app that received fewer notifications than it did.
    for malformed in ["not json", #"{"bundleID":"com.foo"}"#] {
      XCTAssertThrowsError(try DeliveredNotification.records(fromBridgeOutput: "\(record)\n\(malformed)")) { error in
        guard let error = error as? SimulatorNotificationError,
          case let .undecodableDeliveredNotification(line, _) = error
        else {
          XCTFail("'\(malformed)' should fail the read; threw \(error)")
          return
        }
        XCTAssertEqual(line, malformed)
      }
    }
  }
}
