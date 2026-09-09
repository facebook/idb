/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

private let DeviceSetEnvKey = "FBSIMULATORCONTROL_DEVICE_SET"
private let DeviceSetEnvDefault = "default"

private let LaunchTypeEnvKey = "FBSIMULATORCONTROL_LAUNCH_TYPE"
private let LaunchTypeSimulatorApp = "simulator_app"

/// The Boot suite: the one place that creates and boots a simulator of its own, because that
/// lifecycle is what it covers. Everything else needing a booted simulator takes one from its
/// environment instead — see `ProvidedSimulatorTestCase`.
final class SimulatorBootTestCase: XCTestCase {

  private var control: SimulatorControlBootstrap!
  private var simulatorConfiguration: FBSimulatorConfiguration!
  private var bootConfiguration: FBSimulatorBootConfiguration!

  override class func setUp() {
    super.setUp()
    if ProcessInfo.processInfo.environment[FBControlCoreStderrLogging] == nil {
      setenv(FBControlCoreStderrLogging, "YES", 1)
    }
    if ProcessInfo.processInfo.environment[FBControlCoreDebugLogging] == nil {
      setenv(FBControlCoreDebugLogging, "NO", 1)
    }
    FBControlCoreGlobalConfiguration.defaultLogger.log("Current Configuration => \(String(describing: FBControlCoreGlobalConfiguration.description))")
  }

  override func setUpWithError() throws {
    continueAfterFailure = false
    // Creating and booting a simulator can take minutes on a slow CI host; when the harness
    // enforces per-test time allowances, claim more than the short suite-wide default.
    executionTimeAllowance = 600
    // Memoized: a no-op after the first load. Throwing here turns a load failure into a test
    // failure instead of killing the runner.
    try FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(FBControlCoreGlobalConfiguration.defaultLogger)
    simulatorConfiguration = try FBSimulatorConfiguration.defaultConfiguration().withDeviceModel(.modeliPhone16)
    bootConfiguration = FBSimulatorBootConfiguration(options: Self.bootOptions, environment: [:])
    let noLogger: (any FBControlCoreLogger)? = nil
    control = try SimulatorControlBootstrap.withConfiguration(
      FBSimulatorControlConfiguration(deviceSetPath: Self.deviceSetPath, logger: noLogger))
  }

  override func tearDown() async throws {
    // Whatever the test left behind, in whichever set it used.
    if let control {
      try? await control.set.shutdownAll()
    }
    control = nil
  }

  func testBootShutdownLifecycle() async throws {
    do {
      try simulatorConfiguration.checkRuntimeRequirements()
    } catch {
      // An unsatisfiable configuration is a property of the host, not of the code under test.
      // Every other failure below is thrown, because an acquisition problem must never pass.
      throw XCTSkip("The host cannot create a simulator for \(simulatorConfiguration!): \(error)")
    }

    let simulator = try await control.set.createSimulator(with: simulatorConfiguration)
    try await simulator.lifecycle.boot(bootConfiguration)
    XCTAssertEqual(simulator.state, .booted)

    try await simulator.shutdown()
    XCTAssertEqual(simulator.state, .shutdown)
    // Deletion, not erasure: an erased device lingers in the set reporting a transient `creating`
    // state while its contents are rebuilt.
    try await control.set.delete(simulator)
  }

  private static var bootOptions: SimulatorBootOptions {
    // Direct launch unless the environment asks for Simulator.app.
    ProcessInfo.processInfo.environment[LaunchTypeEnvKey] == LaunchTypeSimulatorApp ? [] : [.tieToProcessLifecycle]
  }

  private static var deviceSetPath: String? {
    // An isolated set unless explicitly opted into the default one, which holds the developer's
    // own simulators — and teardown shuts down every booted device in whichever set is used.
    if ProcessInfo.processInfo.environment[DeviceSetEnvKey] == DeviceSetEnvDefault {
      return nil
    }
    return (NSTemporaryDirectory() as NSString).appendingPathComponent("FBSimulatorBootTests_CustomSet")
  }
}
