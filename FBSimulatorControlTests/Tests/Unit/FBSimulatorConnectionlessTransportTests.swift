/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

/// The two connectionless transports — Purple for GSEvents, Darwin notifications for shake and the
/// in-call status bar — hold their target weakly and reach it on every send, since neither keeps a
/// connection open. That makes "the target is gone" a real state each has to handle, and it is the one
/// part of either that can be exercised without a live simulator.
///
/// Both were `guard let simulator else { throw }` written inline on `FBSimulatorHID` before they became
/// transports of their own. This pins that the contract came with them.
final class FBSimulatorConnectionlessTransportTests: XCTestCase {

  private func assertDeallocatedTarget(
    _ operation: () throws -> Void,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(try operation(), message, file: file, line: line) { error in
      guard case FBWeakTargetError.deallocated = error else {
        return XCTFail("\(message): expected a weak-target failure, got \(error)", file: file, line: line)
      }
    }
  }

  func testPurpleTransportReportsADeallocatedTarget() {
    let purple = FBSimulatorPurpleHIDTransport(simulator: nil)

    assertDeallocatedTarget({ try purple.sendOrientation(.landscapeLeft) }, "orientation")
    assertDeallocatedTarget({ try purple.sendLockDevice() }, "lock")
  }

  func testDarwinNotificationTransportReportsADeallocatedTarget() {
    let notification = FBSimulatorDarwinNotificationTransport(simulator: nil)

    assertDeallocatedTarget({ try notification.sendShake() }, "shake")
    assertDeallocatedTarget({ try notification.sendToggleInCallStatusBar() }, "in-call status bar")
  }
}
