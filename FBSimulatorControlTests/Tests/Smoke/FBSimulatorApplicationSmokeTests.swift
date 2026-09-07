/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

/// Drives the application lifecycle — launch, process lookup, terminate — against the
/// provided booted simulator, using a system application so no fixture installation (or
/// fixture architecture) is involved.
final class FBSimulatorApplicationSmokeTests: FBProvidedSimulatorTestCase {

  func testLaunchesAndTerminatesSystemApplication() async throws {
    let simulator = self.simulator!
    let bundleID = "com.apple.mobilesafari"
    let io: FBProcessIO<AnyObject, AnyObject, AnyObject> = .outputToDevNull()
    let configuration = FBApplicationLaunchConfiguration(
      bundleID: bundleID,
      bundleName: nil,
      arguments: [],
      environment: [:],
      waitForDebugger: false,
      io: io,
      launchMode: .relaunchIfRunning)

    let launched = try await simulator.launchApplication(configuration)
    XCTAssertGreaterThan(launched.processIdentifier, 0)

    let processID = try await simulator.processID(forBundleID: bundleID)
    XCTAssertEqual(processID, launched.processIdentifier)

    try await simulator.killApplication(bundleID: bundleID)
    do {
      let survivor = try await simulator.processID(forBundleID: bundleID)
      XCTFail("\(bundleID) should not be running after termination, found pid \(survivor)")
    } catch {
      // The bundle id resolving to no running process is the expected outcome.
    }
  }
}
