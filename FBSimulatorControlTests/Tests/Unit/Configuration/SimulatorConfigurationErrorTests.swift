/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import Testing

@Suite
struct SimulatorConfigurationErrorTests {
  @Test
  func resolutionErrorsDescribeTheRuntimeIndex() {
    #expect(SimulatorConfigurationError.noMatchingRuntime(available: "[]").errorDescription == "Could not obtain matching SimRuntime, no matches. Available Runtimes []")
    #expect(SimulatorConfigurationError.noMatchingDeviceType(available: "[]").errorDescription == "Could not obtain matching DeviceTypes, no matches. Available Device Types []")
    #expect(SimulatorConfigurationError.ambiguousDeviceType(matches: "[first, second]").description == "Matching Device Types is ambiguous: [first, second]")
  }
}
