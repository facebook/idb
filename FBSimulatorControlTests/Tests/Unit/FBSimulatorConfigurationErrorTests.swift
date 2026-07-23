/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class FBSimulatorConfigurationErrorTests: XCTestCase {

  func testMessagesAreStable() {
    XCTAssertEqual(
      FBSimulatorConfigurationError.noNewestAvailableOS(device: "iPhone 6").errorDescription,
      "No newest available OS for device iPhone 6"
    )
    XCTAssertEqual(
      FBSimulatorConfigurationError.unsupportedDevice(name: "FooPad").errorDescription,
      "Could not obtain Device for FooPad, perhaps it is unsupported by FBSimulatorControl"
    )
    XCTAssertEqual(
      FBSimulatorConfigurationError.noDefaultDeviceTypeRegistered(model: "iPhone 6").errorDescription,
      "No device type is registered for 'iPhone 6'"
    )
    XCTAssertEqual(
      FBSimulatorConfigurationError.noAvailableOSVersionsForDefault.errorDescription,
      "No available OS versions for the default simulator configuration"
    )
  }

  func testRuntimeUnavailableComposesReason() {
    XCTAssertEqual(
      FBSimulatorConfigurationError.runtimeUnavailable(configuration: "Device 'X' | OS 'Y'", reason: "no matches").errorDescription,
      "Could not obtain available SimRuntime for configuration Device 'X' | OS 'Y': no matches"
    )
    XCTAssertEqual(
      FBSimulatorConfigurationError.runtimeUnavailable(configuration: "Device 'X' | OS 'Y'", reason: nil).errorDescription,
      "Could not obtain available SimRuntime for configuration Device 'X' | OS 'Y'"
    )
  }
}
