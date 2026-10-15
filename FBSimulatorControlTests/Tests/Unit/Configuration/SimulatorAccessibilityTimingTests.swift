/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import Testing

@Suite("Accessibility read timing")
struct SimulatorAccessibilityTimingTests {
  @Test func theDefaultsBoundAnElementAtFiveSecondsAndAQueryAtTen() {
    #expect(SimulatorAccessibilityTiming.default == SimulatorAccessibilityTiming(elementTimeout: 5, queryTimeout: 10))
  }

  @Test func aSetsConfigurationCarriesItsTimingAndDefaultsToTheDefaults() {
    let timing = SimulatorAccessibilityTiming(elementTimeout: 1, queryTimeout: 3)
    #expect(SimulatorControlConfiguration(deviceSetPath: nil, logger: nil, accessibilityTiming: timing).accessibilityTiming == timing)
    #expect(SimulatorControlConfiguration(deviceSetPath: nil, logger: nil).accessibilityTiming == .default)
  }

  @Test func aSimulatorCarriesTheTimingItWasGiven() {
    let timing = SimulatorAccessibilityTiming(elementTimeout: 2, queryTimeout: 4)
    let base = SimulatorTestSupport.testableSimulator()
    let simulator = Simulator(
      device: base.device, configuration: base.configuration, auxillaryDirectory: base.auxillaryDirectory, logger: nil,
      accessibilityTiming: timing)
    #expect(simulator.accessibilityTiming == timing)
  }
}
