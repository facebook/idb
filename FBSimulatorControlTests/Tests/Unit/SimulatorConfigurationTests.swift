/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

final class SimulatorConfigurationTests: XCTestCase {
  func testCreationRequestKeepsDeviceAndRuntimeSelectionExplicit() {
    let request = SimulatorCreationRequest(device: .identifier("future.device"), runtime: .name("FutureOS 99.0"))
    XCTAssertEqual(request.device, .identifier("future.device"))
    XCTAssertEqual(request.runtime, .name("FutureOS 99.0"))
  }

  func testOmittedRuntimeIsResolvedAgainstTheRequestedDevice() throws {
    let request = SimulatorCreationRequest(device: .identifier("future.device"))
    let index = SimulatorRuntimeIndex(
      devices: [.init(identifier: "future.device", name: "Future Device")],
      runtimes: [
        .init(identifier: "incompatible", name: "OtherOS 100.0", version: "100.0", build: "100A1", available: true, supportedDevices: []),
        .init(identifier: "compatible", name: "FutureOS 99.0", version: "99.0", build: "99A1", available: true, supportedDevices: ["future.device"]),
      ])
    XCTAssertNil(request.runtime)
    let match = try index.resolve(request)
    XCTAssertEqual(index.runtimes[match.runtime].identifier, "compatible")
  }
}
