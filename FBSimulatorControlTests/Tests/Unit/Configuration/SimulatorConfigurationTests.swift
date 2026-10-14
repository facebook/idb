/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import Testing

@Suite
struct SimulatorConfigurationTests {
  @Test
  func creationRequestKeepsDeviceAndRuntimeSelectionExplicit() {
    let request = SimulatorCreationRequest(device: .identifier("future.device"), runtime: .name("FutureOS 99.0"))
    #expect(request.device == .identifier("future.device"))
    #expect(request.runtime == .name("FutureOS 99.0"))
  }

  @Test
  func omittedRuntimeIsResolvedAgainstTheRequestedDevice() throws {
    let request = SimulatorCreationRequest(device: .identifier("future.device"))
    let index = SimulatorRuntimeIndex(
      devices: [.init(identifier: "future.device", name: "Future Device")],
      runtimes: [
        .init(identifier: "incompatible", name: "OtherOS 100.0", version: "100.0", build: "100A1", available: true, supportedDevices: []),
        .init(identifier: "compatible", name: "FutureOS 99.0", version: "99.0", build: "99A1", available: true, supportedDevices: ["future.device"]),
      ])
    #expect(request.runtime == nil)
    let match = try index.resolve(request)
    #expect(index.runtimes[match.runtime].identifier == "compatible")
  }
}
