/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
@testable import FBSimulatorVideo
import Testing

/// Every command accessor FBSimulatorVideo adds to `Simulator`.
enum SimulatorVideoCommandAccessor: CaseIterable, Sendable {
  case videoRecording
  case videoStream

  func resolve(on simulator: Simulator) {
    switch self {
    case .videoRecording:
      _ = simulator.videoRecording
    case .videoStream:
      _ = simulator.videoStream
    }
  }
}

@Suite("Simulator video command retention")
struct SimulatorVideoCommandRetentionTests {
  @Test("Resolving a command does not retain the simulator", arguments: SimulatorVideoCommandAccessor.allCases)
  func resolvingACommandDoesNotRetainTheSimulator(_ accessor: SimulatorVideoCommandAccessor) {
    #expect(simulatorSurvives { accessor.resolve(on: $0) } == false)
  }
}
