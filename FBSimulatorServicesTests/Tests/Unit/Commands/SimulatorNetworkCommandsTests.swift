/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
@testable import FBSimulatorServices
import Foundation
import Testing

@Suite
struct SimulatorNetworkCommandsTests {

  // MARK: - Helpers

  private func makeSimulator() -> Simulator {
    SimulatorTestSupport.testableSimulator()
  }

  private func assertThrowsAsync(
    _ message: String,
    _ expression: () async throws -> Void,
    expecting isExpected: (SimulatorNetworkError) -> Bool
  ) async {
    do {
      try await expression()
      Issue.record(Comment(rawValue: message))
    } catch let error as SimulatorNetworkError where isExpected(error) {
      // Expected.
    } catch {
      Issue.record("\(message); threw \(error)")
    }
  }

  // MARK: - DNS Validation

  @Test
  func dnsSetRejectsEmptyArray() async {
    let simulator = makeSimulator()
    await assertThrowsAsync(
      "dns.set should reject an empty array",
      {
        try await simulator.network.dns.set([])
      }
    ) { if case .noDnsServers = $0 { return true } else { return false } }
  }
}
