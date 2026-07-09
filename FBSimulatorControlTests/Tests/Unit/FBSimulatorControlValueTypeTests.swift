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

final class FBSimulatorControlValueTypeTests: XCTestCase {

  func testHIDEvents() {
    // FBSimulatorHIDEvent is a value type: each event must equal (and hash equal to) an
    // independently-constructed identical event.
    let events: [FBSimulatorHIDEvent] = [
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
    let copies: [FBSimulatorHIDEvent] = [
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
}
