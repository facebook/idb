/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

/// Runs the runtime's `launchctl` inside the provided booted simulator via `FBSimulator.launchProcessConsumingOutput`.
final class FBSimulatorLaunchCtlTests: FBProvidedSimulatorTestCase {

  func testListsServicesViaCoreSimulatorSpawn() async throws {
    let services = try await skippingIfGuestServiceSpawnUnavailable {
      try await simulator.listServices()
    }
    XCTAssertFalse(services.isEmpty, "A booted simulator should report launchd services")
  }
}
