/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import FBControlCore
@testable import FBSimulatorControl
import XCTest

private let DeviceSetEnvKey = "FBSIMULATORCONTROL_DEVICE_SET"
private let DeviceSetEnvDefault = "default"

// A new simulator is not usable until its first boot has run data migration, which takes around
// five minutes on a hosted CI runner. Bounded below the test's execution allowance so a slow
// boot fails with the poll's own error rather than being killed.
private let UsableTimeout: TimeInterval = 540

private let LaunchTypeEnvKey = "FBSIMULATORCONTROL_LAUNCH_TYPE"
private let LaunchTypeSimulatorApp = "simulator_app"

/// The Boot suite: the one place that creates and boots a simulator of its own, because that
/// lifecycle is what it covers. Everything else needing a booted simulator takes one from its
/// environment instead — see `ProvidedSimulatorTestCase`.
///
/// Booting has two completion criteria and a test for each: returning once the simulator reports
/// `.booted`, and returning once it is usable.
final class SimulatorBootTestCase: XCTestCase {

  private var control: SimulatorControlBootstrap!
  private var creationRequest: SimulatorCreationRequest!
  private var expectedConfiguration: SimulatorConfiguration!
  private var ownedSimulator: Simulator?
  private var ownedDeviceSetPath: String?

  override class func setUp() {
    super.setUp()
    if ProcessInfo.processInfo.environment[FBControlCoreStderrLogging] == nil {
      setenv(FBControlCoreStderrLogging, "YES", 1)
    }
    if ProcessInfo.processInfo.environment[FBControlCoreDebugLogging] == nil {
      setenv(FBControlCoreDebugLogging, "NO", 1)
    }
    ControlCoreGlobalConfiguration.defaultLogger.log("Current Configuration => \(ControlCoreGlobalConfiguration.description)")
  }

  override func setUpWithError() throws {
    continueAfterFailure = false
    // Booting can take minutes on a loaded host, far longer than the default allowance.
    executionTimeAllowance = 600
    // Throwing here turns a load failure into a test failure instead of killing the runner.
    try SimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(ControlCoreGlobalConfiguration.defaultLogger)
    let service = try SimulatorServiceContext.sharedServiceContext()
    let deviceTypes = service.supportedDeviceTypes()
    let runtimes = service.supportedRuntimes()
    guard
      let availableDevice = deviceTypes.first(where: { device in
        device.productFamilyID == 1 && runtimes.contains(where: { $0.available && $0.supportsDeviceType(device) })
      })
    else {
      throw XCTSkip("The host has no available runtime compatible with an iPhone")
    }
    creationRequest = SimulatorCreationRequest(device: .identifier(try XCTUnwrap(availableDevice.identifier)))
    let snapshot = CoreSimulatorRuntimeIndex(deviceTypes: deviceTypes, runtimes: runtimes)
    let (deviceType, runtime) = try snapshot.resolve(creationRequest)
    expectedConfiguration = SimulatorConfiguration.configuration(deviceType: deviceType, runtime: runtime)
    let noLogger: (any ControlCoreLogger)? = nil
    ownedDeviceSetPath = Self.deviceSetPath
    control = try SimulatorControlBootstrap.withConfiguration(
      SimulatorControlConfiguration(deviceSetPath: ownedDeviceSetPath, logger: noLogger))
  }

  override func tearDown() async throws {
    let deviceSetPath = control?.set.deviceSet.setPath
    if let simulator = ownedSimulator {
      try await control.set.delete(simulator)
      ownedSimulator = nil
    }
    control = nil
    if let ownedDeviceSetPath {
      if FileManager.default.fileExists(atPath: ownedDeviceSetPath) {
        try FileManager.default.removeItem(atPath: ownedDeviceSetPath)
      }
      self.ownedDeviceSetPath = nil
      XCTAssertFalse(FileManager.default.fileExists(atPath: ownedDeviceSetPath), "Temporary device set remains at \(ownedDeviceSetPath)")
    } else if let deviceSetPath {
      XCTAssertTrue(FileManager.default.fileExists(atPath: deviceSetPath), "The shared default device set must remain")
    }
  }

  func testBootShutdownLifecycle() async throws {
    let simulator = try await bootedSimulator()
    XCTAssertEqual(simulator.configuration.deviceTypeIdentifier, expectedConfiguration.deviceTypeIdentifier)
    XCTAssertEqual(simulator.configuration.runtimeIdentifier, expectedConfiguration.runtimeIdentifier)
    XCTAssertEqual(simulator.configuration.os.versionString, expectedConfiguration.os.versionString)
    XCTAssertEqual(simulator.configuration.deviceTypeIdentifier, simulator.device.deviceType.identifier)
    XCTAssertEqual(simulator.configuration.runtimeIdentifier, simulator.device.runtime.identifier)
    // CoreSimulator can choose another installed build for the same runtime identifier.
    XCTAssertEqual(simulator.configuration.runtimeBuildVersion, simulator.device.runtime.buildVersionString)
    XCTAssertEqual(simulator.state, .booted)

    try await shutdownAndDelete(simulator)
  }

  /// Booting without `.verifyUsable` returns on the state alone, so the simulator may still be
  /// coming up; `resolveUsable` is how a caller that wanted the state first waits for the rest.
  func testStateBootReturnsBeforeUsableAndResolvesAfterwards() async throws {
    let simulator = try await bootedSimulator()
    XCTAssertEqual(simulator.state, .booted)

    try await simulator.lifecycle.resolveUsable(deadline: PollDeadline(timeout: UsableTimeout, waitingFor: "the simulator to become usable"))
    XCTAssertEqual(simulator.device.bootStatus()?.isTerminalStatus, true)

    try await shutdownAndDelete(simulator)
  }

  /// Booting with `.verifyUsable` does that waiting itself, so the simulator is usable by the time
  /// the call returns.
  func testUsableBootReturnsOnlyOnceTheSimulatorIsUsable() async throws {
    let simulator = try await bootedSimulator(adding: .verifyUsable)
    XCTAssertEqual(simulator.state, .booted)
    XCTAssertEqual(simulator.device.bootStatus()?.isTerminalStatus, true)

    try await shutdownAndDelete(simulator)
  }

  private func bootedSimulator(adding options: SimulatorBootOptions = []) async throws -> Simulator {
    let simulator = try await control.set.createSimulator(with: creationRequest)
    ownedSimulator = simulator
    try await simulator.lifecycle.boot(SimulatorBootConfiguration(options: Self.bootOptions.union(options), environment: [:]))
    return simulator
  }

  private func shutdownAndDelete(_ simulator: Simulator) async throws {
    try await simulator.power.shutdown()
    XCTAssertEqual(simulator.state, .shutdown)
    try await control.set.delete(simulator)
    ownedSimulator = nil
  }

  private static var bootOptions: SimulatorBootOptions {
    ProcessInfo.processInfo.environment[LaunchTypeEnvKey] == LaunchTypeSimulatorApp ? [] : [.tieToProcessLifecycle]
  }

  private static var deviceSetPath: String? {
    // Even in the default set, teardown deletes only the simulator created by this test.
    if ProcessInfo.processInfo.environment[DeviceSetEnvKey] == DeviceSetEnvDefault {
      return nil
    }
    return (NSTemporaryDirectory() as NSString).appendingPathComponent("FBSimulatorBootTests_\(UUID().uuidString)")
  }
}
