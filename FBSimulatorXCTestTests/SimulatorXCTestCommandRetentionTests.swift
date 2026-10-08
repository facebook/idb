/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
@testable import FBSimulatorXCTest
import Testing

/// Every command accessor FBSimulatorXCTest adds to `Simulator`.
enum SimulatorXCTestCommandAccessor: CaseIterable, Sendable {
  case xctest
  case repl

  func resolve(on simulator: Simulator) {
    switch self {
    case .xctest:
      _ = simulator.xctest
    case .repl:
      _ = simulator.repl
    }
  }
}

@Suite("Simulator XCTest command retention")
struct SimulatorXCTestCommandRetentionTests {
  @Test("Resolving a command does not retain the simulator", arguments: SimulatorXCTestCommandAccessor.allCases)
  func resolvingACommandDoesNotRetainTheSimulator(_ accessor: SimulatorXCTestCommandAccessor) {
    #expect(simulatorSurvives { accessor.resolve(on: $0) } == false)
  }
}
