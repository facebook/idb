/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

final class SimulatorNetworkCommandsTests: XCTestCase {

  // MARK: - Helpers

  private func makeSimulator() -> FBSimulator {
    SimulatorTestSupport.testableSimulator()
  }

  private func assertThrowsAsync(
    _ message: String,
    _ expression: () async throws -> Void,
    expecting isExpected: (SimulatorNetworkError) -> Bool
  ) async {
    do {
      try await expression()
      XCTFail(message)
    } catch let error as SimulatorNetworkError where isExpected(error) {
      // Expected.
    } catch {
      XCTFail("\(message); threw \(error)")
    }
  }

  // MARK: - DNS Validation

  func testSetDnsServersRejectsEmptyArray() async {
    let simulator = makeSimulator()
    await assertThrowsAsync(
      "setDnsServers should reject empty array",
      {
        try await simulator.network.setDnsServers([])
      }
    ) { if case .noDnsServers = $0 { return true } else { return false } }
  }
}
