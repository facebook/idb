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

/// The connectionless Purple transport holds its target weakly and reaches it on every send, since it
/// keeps no connection open. That makes "the target is gone" a real state it has to handle, and it is
/// the one part of it that can be exercised without a live simulator.
final class SimulatorConnectionlessTransportTests: XCTestCase {

  private func assertDeallocatedTarget(
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("\(message): expected a weak-target failure, got success", file: file, line: line)
    } catch WeakTargetError.deallocated {
    } catch {
      XCTFail("\(message): expected a weak-target failure, got \(error)", file: file, line: line)
    }
  }

  func testPurpleTransportReportsADeallocatedTarget() async {
    let purple = SimulatorPurpleHIDTransport(simulator: nil)

    await assertDeallocatedTarget("orientation") { try await purple.sendOrientation(.landscapeLeft) }
    await assertDeallocatedTarget("lock") { try await purple.sendLockDevice() }
  }

  // The failure has to survive the hop back from the private queue; concurrent sends each get their own.
  func testDeallocatedTargetSurvivesConcurrentSends() async {
    let purple = SimulatorPurpleHIDTransport(simulator: nil)

    await withTaskGroup(of: Bool.self) { group in
      for _ in 0..<8 {
        group.addTask {
          do {
            try await purple.sendLockDevice()
            return false
          } catch WeakTargetError.deallocated {
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
      XCTAssertEqual(reported, 8, "every concurrent send gets its own failure back")
    }
  }
}
