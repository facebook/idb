/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

/// Runs the `SimulatorFrameworkBridge` helper inside the provided booted simulator via `FBSimulator.launchProcessConsumingOutput`, under the CoreSimulator launchd domain.
final class FBSimulatorSettingsBridgeTests: FBProvidedSimulatorTestCase {

  func testRunsSimulatorFrameworkBridgeViaCoreSimulator() async throws {
    _ = try await skippingIfGuestServiceSpawnUnavailable {
      try await simulator.listProxy()
    }
    _ = try await simulator.listDns()
  }

  func testAutoFillPasswordsRoundTripsThroughApply() async throws {
    let simulator = self.simulator!
    let original = try await skippingIfGuestServiceSpawnUnavailable {
      try await simulator.getCurrentPreference("AutoFillPasswords", domain: nil)
    }
    addTeardownBlock {
      // Leased-resource discipline: restore the toggle this test mutates.
      try await simulator.apply(.autoFillPasswords(original != "0"))
    }
    try await simulator.apply(.autoFillPasswords(false))
    // nil domain == Apple Global Domain, where apply(.autoFillPasswords) writes the toggle.
    let disabled = try await simulator.getCurrentPreference("AutoFillPasswords", domain: nil)
    try await simulator.apply(.autoFillPasswords(true))
    let enabled = try await simulator.getCurrentPreference("AutoFillPasswords", domain: nil)
    XCTAssertNotEqual(disabled, enabled, "AutoFillPasswords should read back differently after disable vs enable")
    let viaSettingValue = try await simulator.currentSettingValue(name: "autofill-passwords", domain: nil)
    XCTAssertEqual(viaSettingValue, enabled, "currentSettingValue should read autofill-passwords from its real backing")
  }
}
