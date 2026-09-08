/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

extension FBSimulatorControlTestCase {

  /// Creates a simulator for the given configuration.
  ///
  /// An unsatisfiable configuration — no installed runtime supports it — skips the test: that is
  /// a property of the host, not the code under test. Every other failure is thrown so the test
  /// fails; acquisition problems must never silently pass.
  func obtainSimulator(with configuration: FBSimulatorConfiguration) async throws -> FBSimulator {
    do {
      try configuration.checkRuntimeRequirements()
    } catch {
      throw XCTSkip("The host cannot create a simulator for \(configuration): \(error)")
    }
    return try await control.set.createSimulator(with: configuration)
  }

  func obtainBootedSimulator(
    with configuration: FBSimulatorConfiguration,
    bootConfiguration: FBSimulatorBootConfiguration
  ) async throws -> FBSimulator {
    let simulator = try await obtainSimulator(with: configuration)
    try await simulator.boot(bootConfiguration)
    XCTAssertEqual(simulator.state, .booted)
    return simulator
  }

  /// Boots a simulator with the test case's default configuration.
  func obtainBootedSimulator() async throws -> FBSimulator {
    try await obtainBootedSimulator(with: simulatorConfiguration, bootConfiguration: bootConfiguration)
  }

  /// Shuts the simulator down and deletes it from the set. Deletion (not erasure) is the
  /// right cleanup for suite-created simulators: erased devices linger in the device set and
  /// report a transient `creating` state while their contents are rebuilt.
  func shutdownAndDelete(_ simulator: FBSimulator) async throws {
    try await simulator.shutdown()
    XCTAssertEqual(simulator.state, .shutdown)
    try await control.set.delete(simulator)
  }
}
