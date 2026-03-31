// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import Carbon
import Foundation
import XCTest

@testable import FBSimulatorControl

final class FBSimulatorControlValueTypeTests: FBControlCoreValueTestCase {

  func testHIDEvents() {
    let values: [NSObject] = [
      FBSimulatorHIDEvent.tapAt(x: 10, y: 20) as! NSObject,
      FBSimulatorHIDEvent.shortButtonPress(.applePay) as! NSObject,
      FBSimulatorHIDEvent.shortButtonPress(.homeButton) as! NSObject,
      FBSimulatorHIDEvent.shortButtonPress(.lock) as! NSObject,
      FBSimulatorHIDEvent.shortButtonPress(.sideButton) as! NSObject,
      FBSimulatorHIDEvent.shortButtonPress(.siri) as! NSObject,
      FBSimulatorHIDEvent.shortButtonPress(.homeButton) as! NSObject,
      FBSimulatorHIDEvent.shortKeyPress(UInt32(kVK_ANSI_W)) as! NSObject,
      FBSimulatorHIDEvent.shortKeyPress(UInt32(kVK_ANSI_A)) as! NSObject,
      FBSimulatorHIDEvent.shortKeyPress(UInt32(kVK_ANSI_R)) as! NSObject,
      FBSimulatorHIDEvent.shortKeyPress(UInt32(kVK_ANSI_I)) as! NSObject,
      FBSimulatorHIDEvent.shortKeyPress(UInt32(kVK_ANSI_O)) as! NSObject,
    ]
    assertEquality(ofCopy: values)
  }
}
