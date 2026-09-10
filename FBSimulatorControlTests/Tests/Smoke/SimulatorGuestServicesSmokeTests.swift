/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

/// Everything the host asks a booted simulator to run on its behalf, in one sequence: the
/// runtime's own `launchctl` spawned through CoreSimulator, the `SimulatorFrameworkBridge` helper
/// spawned into the launchd domain, a settings write read back through its real backing, and an
/// application launched and terminated.
///
/// One test, because the expensive part of a smoke test is acquiring a simulator, not asserting
/// against one: `setUp` runs per test case, so every case split off here is another boot to pay
/// for. These checks share a target and a mechanism, so they share a case, and each step is
/// assertive enough that a failure names itself.
final class SimulatorGuestServicesSmokeTests: ProvidedSimulatorTestCase {

  private static let bundleID = "com.apple.mobilesafari"

  func testGuestServesLaunchCtlBridgeSettingsAndApplications() async throws {
    let simulator = self.simulator!

    // The runtime's own launchctl, spawned via CoreSimulator.
    let services = try await skippingIfGuestServiceSpawnUnavailable {
      try await simulator.launchCtl.listServices()
    }
    XCTAssertFalse(services.isEmpty, "A booted simulator should report launchd services")

    // The SimulatorFrameworkBridge helper, spawned into the booted launchd domain.
    _ = try await simulator.network.listProxy()
    _ = try await simulator.network.listDns()

    // A settings write, read back through the backing the getter actually consults.
    let original = try await simulator.preferences.getCurrentPreference("AutoFillPasswords", domain: nil)
    addTeardownBlock {
      // Leased-resource discipline: restore the toggle this test mutates.
      try await simulator.preferences.apply(.autoFillPasswords(original != "0"))
    }
    try await simulator.preferences.apply(.autoFillPasswords(false))
    // nil domain == Apple Global Domain, where apply(.autoFillPasswords) writes the toggle.
    let disabled = try await simulator.preferences.getCurrentPreference("AutoFillPasswords", domain: nil)
    try await simulator.preferences.apply(.autoFillPasswords(true))
    let enabled = try await simulator.preferences.getCurrentPreference("AutoFillPasswords", domain: nil)
    XCTAssertNotEqual(disabled, enabled, "AutoFillPasswords should read back differently after disable vs enable")
    let viaSettingValue = try await simulator.preferences.currentSettingValue(name: "autofill-passwords", domain: nil)
    XCTAssertEqual(viaSettingValue, enabled, "currentSettingValue should read autofill-passwords from its real backing")

    // An application through its whole lifecycle. A system application, so nothing has to be
    // installed and no fixture architecture is involved.
    let io: FBProcessIO<AnyObject, AnyObject, AnyObject> = .outputToDevNull()
    let configuration = FBApplicationLaunchConfiguration(
      bundleID: Self.bundleID,
      bundleName: nil,
      arguments: [],
      environment: [:],
      waitForDebugger: false,
      io: io,
      launchMode: .relaunchIfRunning)
    let launched = try await simulator.application.launch(configuration)
    XCTAssertGreaterThan(launched.processIdentifier, 0)
    let processID = try await simulator.application.processID(forBundleID: Self.bundleID)
    XCTAssertEqual(processID, launched.processIdentifier)

    try await simulator.application.kill(bundleID: Self.bundleID)
    do {
      let survivor = try await simulator.application.processID(forBundleID: Self.bundleID)
      XCTFail("\(Self.bundleID) should not be running after termination, found pid \(survivor)")
    } catch {
      // The bundle id resolving to no running process is the expected outcome.
    }
  }
}
