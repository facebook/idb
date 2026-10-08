/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBAXCore
@testable import FBSimulatorAX
@testable import FBSimulatorControl
import Testing

/// Every command accessor FBSimulatorAX adds to `Simulator`.
enum SimulatorAccessibilityCommandAccessor: CaseIterable, Sendable {
  case uiAutomation
  case accessibility

  func resolve(on simulator: Simulator) {
    switch self {
    case .uiAutomation:
      // Every backend, since only the persistent axbridge scopes resolve a transport into the cache.
      for name in UIAutomationBackendName.allCases {
        _ = try? simulator.uiAutomation(backend: UIAutomationBackend(resolvedName: name))
      }
    case .accessibility:
      _ = simulator.accessibility
    }
  }
}

@Suite("Simulator accessibility command retention")
struct SimulatorAccessibilityCommandRetentionTests {
  @Test("Resolving a command does not retain the simulator", arguments: SimulatorAccessibilityCommandAccessor.allCases)
  func resolvingACommandDoesNotRetainTheSimulator(_ accessor: SimulatorAccessibilityCommandAccessor) {
    #expect(simulatorSurvives { accessor.resolve(on: $0) } == false)
  }
}
