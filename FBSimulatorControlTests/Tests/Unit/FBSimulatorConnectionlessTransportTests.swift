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
final class FBSimulatorConnectionlessTransportTests: XCTestCase {

  private func assertDeallocatedTarget(
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("\(message): expected a weak-target failure, got success", file: file, line: line)
    } catch FBWeakTargetError.deallocated {
    } catch {
      XCTFail("\(message): expected a weak-target failure, got \(error)", file: file, line: line)
    }
  }

  func testPurpleTransportReportsADeallocatedTarget() async {
    let purple = FBSimulatorPurpleHIDTransport(simulator: nil)

    await assertDeallocatedTarget("orientation") { try await purple.sendOrientation(.landscapeLeft) }
    await assertDeallocatedTarget("lock") { try await purple.sendLockDevice() }
  }

  func testDarwinNotificationTransportReportsADeallocatedTarget() async {
    let notification = FBSimulatorDarwinNotificationTransport(simulator: nil)

    await assertDeallocatedTarget("shake") { try await notification.sendShake() }
    await assertDeallocatedTarget("in-call status bar") { try await notification.sendToggleInCallStatusBar() }
  }

  // The failure has to survive the hop back from the private queue; concurrent sends each get their own.
  func testDeallocatedTargetSurvivesConcurrentSends() async {
    let purple = FBSimulatorPurpleHIDTransport(simulator: nil)
    let notification = FBSimulatorDarwinNotificationTransport(simulator: nil)

    await withTaskGroup(of: Bool.self) { group in
      for _ in 0..<8 {
        group.addTask {
          do {
            try await purple.sendLockDevice()
            return false
          } catch FBWeakTargetError.deallocated {
            return true
          } catch {
            return false
          }
        }
        group.addTask {
          do {
            try await notification.sendShake()
            return false
          } catch FBWeakTargetError.deallocated {
            return true
          } catch {
            return false
          }
        }
      }
      var reported = 0
      for await ok in group where ok {
        reported += 1
      }
      XCTAssertEqual(reported, 16, "every concurrent send gets its own failure back")
    }
  }
}
