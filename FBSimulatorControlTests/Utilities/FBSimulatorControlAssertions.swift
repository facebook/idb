/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

// MARK: - XCTestCase Assertion Helpers

extension XCTestCase {

  func assertShutdownSimulatorAndTerminateSession(_ simulator: FBSimulator) async {
    do {
      try await simulator.shutdown()
    } catch {
      XCTFail("Failed to shutdown simulator: \(error)")
    }

    do {
      try await simulator.erase()
    } catch {
      XCTFail("Failed to erase simulator: \(error)")
    }
    assertSimulatorShutdown(simulator)
  }

  func assertNeedle(_ needle: String, inHaystack haystack: String) {
    XCTAssertNotNil(needle)
    XCTAssertNotNil(haystack)
    if haystack.range(of: needle) != nil {
      return
    }
    XCTFail("needle '\(needle)' to be contained in haystack '\(haystack)'")
  }

  func assertSimulatorBooted(_ simulator: FBSimulator) {
    XCTAssertEqual(simulator.state, .booted)
  }

  func assertSimulatorShutdown(_ simulator: FBSimulator) {
    XCTAssertEqual(simulator.state, .shutdown)
  }

  func assertSimulator(_ simulator: FBSimulator, isRunningApplicationFromConfiguration launchConfiguration: FBApplicationLaunchConfiguration) async {
    do {
      let processID = try await simulator.processID(forBundleID: launchConfiguration.bundleID)
      XCTAssertGreaterThan(processID, 0)
    } catch {
      XCTFail("Failed to get process ID: \(error)")
    }
  }
}

// MARK: - FBSimulatorControlTestCase Assertion Helpers

extension FBSimulatorControlTestCase {

  func assertObtainsSimulatorWithConfiguration(_ configuration: FBSimulatorConfiguration) async throws -> FBSimulator {
    do {
      try configuration.checkRuntimeRequirements()
    } catch {
      struct RuntimeRequirementsUnmet: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
      }
      throw RuntimeRequirementsUnmet(message: "Configuration \(configuration) does not meet the runtime requirements with error \(error)")
    }
    return try await control.set.createSimulator(with: configuration)
  }

  func assertObtainsSimulator() async -> FBSimulator? {
    return try? await assertObtainsSimulatorWithConfiguration(simulatorConfiguration)
  }

  func assertObtainsBootedSimulator() async -> FBSimulator? {
    return await assertObtainsBootedSimulator(with: simulatorConfiguration, bootConfiguration: bootConfiguration)
  }

  func assertObtainsBootedSimulator(withInstalledApplication application: FBBundleDescriptor) async -> FBSimulator? {
    guard let simulator = await assertObtainsBootedSimulator() else { return nil }
    do {
      _ = try await simulator.installApplication(atPath: application.path)
    } catch {
      XCTFail("Failed to install application: \(error)")
      return nil
    }
    return simulator
  }

  func assertObtainsBootedSimulator(with configuration: FBSimulatorConfiguration, bootConfiguration: FBSimulatorBootConfiguration) async -> FBSimulator? {
    guard let simulator = try? await assertObtainsSimulatorWithConfiguration(configuration) else { return nil }
    do {
      try await simulator.boot(bootConfiguration)
    } catch {
      XCTFail("Failed to boot simulator: \(error)")
      return nil
    }
    return simulator
  }

  func assertSimulator(_ simulator: FBSimulator, installs application: FBBundleDescriptor) async -> FBSimulator {
    do {
      _ = try await simulator.installApplication(atPath: application.path)
    } catch {
      XCTFail("Failed to install application: \(error)")
    }
    return simulator
  }

  func assertSimulator(_ simulator: FBSimulator, launches configuration: FBApplicationLaunchConfiguration) async -> FBSimulator {
    do {
      _ = try await simulator.launchApplication(configuration)
    } catch {
      XCTFail("Failed to launch application: \(error)")
    }

    await assertSimulator(simulator, isRunningApplicationFromConfiguration: configuration)
    assertSimulatorBooted(simulator)

    // Second launch should fail
    do {
      _ = try await simulator.launchApplication(configuration)
      XCTFail("Second launch should have failed")
    } catch {
      // Expected
    }

    return simulator
  }

  func assertSimulator(withConfiguration simulatorConfiguration: FBSimulatorConfiguration, boots bootConfiguration: FBSimulatorBootConfiguration, thenLaunchesApplication launchConfiguration: FBApplicationLaunchConfiguration) async -> FBSimulator? {
    guard let simulator = await assertObtainsBootedSimulator(with: simulatorConfiguration, bootConfiguration: bootConfiguration) else { return nil }
    return await assertSimulator(simulator, launches: launchConfiguration)
  }
}
