/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
@testable import FBSimulatorServices
import Testing

/// Every command accessor FBSimulatorServices adds to `Simulator`.
enum SimulatorServicesCommandAccessor: CaseIterable, Sendable {
  case orientation
  case privacy
  case preferences
  case network
  case health
  case contacts
  case photos
  case notification
  case lockScreen

  func resolve(on simulator: Simulator) {
    switch self {
    case .orientation:
      _ = simulator.orientation
    case .privacy:
      _ = simulator.privacy
    case .preferences:
      _ = simulator.preferences
    case .network:
      _ = simulator.network
    case .health:
      _ = simulator.health
    case .contacts:
      _ = simulator.contacts
    case .photos:
      _ = simulator.photos
    case .notification:
      _ = simulator.notification
    case .lockScreen:
      _ = simulator.lockScreen
    }
  }
}

@Suite("Simulator services command retention")
struct SimulatorServicesCommandRetentionTests {
  @Test("Resolving a command does not retain the simulator", arguments: SimulatorServicesCommandAccessor.allCases)
  func resolvingACommandDoesNotRetainTheSimulator(_ accessor: SimulatorServicesCommandAccessor) {
    #expect(simulatorSurvives { accessor.resolve(on: $0) } == false)
  }
}
