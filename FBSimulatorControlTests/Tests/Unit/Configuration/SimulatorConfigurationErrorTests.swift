/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class SimulatorConfigurationErrorTests: XCTestCase {
  func testResolutionErrorsDescribeTheRuntimeIndex() {
    XCTAssertEqual(
      SimulatorConfigurationError.noMatchingRuntime(available: "[]").errorDescription,
      "Could not obtain matching SimRuntime, no matches. Available Runtimes []")
    XCTAssertEqual(
      SimulatorConfigurationError.noMatchingDeviceType(available: "[]").errorDescription,
      "Could not obtain matching DeviceTypes, no matches. Available Device Types []")
    XCTAssertEqual(
      SimulatorConfigurationError.ambiguousDeviceType(matches: "[first, second]").description,
      "Matching Device Types is ambiguous: [first, second]")
  }
}
