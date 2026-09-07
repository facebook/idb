/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

private let DeviceUDIDEnvKey = "DEVICE_UDID"
private let DeviceSetPathEnvKey = "DEVICE_SET_PATH"

private struct ProvidedSimulatorError: Error, LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

/// A test case for tests that need *a* booted simulator but do not own its lifecycle.
///
/// The simulator is resolved in this order:
/// 1. `DEVICE_UDID` names one explicitly, with `DEVICE_SET_PATH` naming its device set
///    (defaulting to the default set). It must exist and already be booted.
/// 2. Otherwise a single booted simulator in that set is adopted — the case where a developer
///    or a CI job booted one before running the suite. Several booted simulators is ambiguous
///    and resolves to neither.
/// 3. Otherwise the case boots one for itself, and shuts it down and deletes it afterwards.
///
/// Only a simulator this case booted is ever torn down: a simulator resolved by 1 or 2 is a
/// leased resource, so tests restore any state they mutate and never boot, shutdown, erase or
/// delete it. The fallback exists so the suite always reports a real result — the alternative
/// is a suite that silently skips wherever nothing hands it a simulator, which is the failure
/// mode these tests were rewritten to remove.
class FBProvidedSimulatorTestCase: XCTestCase {

  private(set) var simulator: FBSimulator!
  private var control: FBSimulatorControl?
  /// Non-nil only when this case booted the simulator, and so must tear it down.
  private var bootedSimulator: FBSimulator?

  override func setUp() async throws {
    continueAfterFailure = false
    try FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(FBControlCoreGlobalConfiguration.defaultLogger)
    let environment = ProcessInfo.processInfo.environment
    let noLogger: (any FBControlCoreLogger)? = nil

    if let udid = environment[DeviceUDIDEnvKey] {
      let configuration = FBSimulatorControlConfiguration(
        deviceSetPath: environment[DeviceSetPathEnvKey],
        logger: noLogger)
      let control = try FBSimulatorControl.withConfiguration(configuration)
      self.control = control
      guard let simulator = control.set.simulator(withUDID: udid) else {
        throw ProvidedSimulatorError(message: "The provided simulator \(udid) is not present in the device set")
      }
      guard simulator.state == .booted else {
        throw ProvidedSimulatorError(message: "The provided simulator \(udid) must already be booted; it is \(simulator.state)")
      }
      self.simulator = simulator
      return
    }

    let providedSetConfiguration = FBSimulatorControlConfiguration(
      deviceSetPath: environment[DeviceSetPathEnvKey],
      logger: noLogger)
    let providedSetControl = try FBSimulatorControl.withConfiguration(providedSetConfiguration)
    let booted = providedSetControl.set.allSimulators.filter { $0.state == .booted }
    if booted.count == 1 {
      control = providedSetControl
      simulator = booted[0]
      return
    }

    let ownSetConfiguration = FBSimulatorControlConfiguration(
      deviceSetPath: Self.fallbackDeviceSetPath,
      logger: noLogger)
    let ownSetControl = try FBSimulatorControl.withConfiguration(ownSetConfiguration)
    control = ownSetControl
    guard let simulatorConfiguration = try Self.bootableiPhoneConfiguration() else {
      throw XCTSkip("No simulator was provided and the host has no runtime that can boot an iPhone")
    }
    let own = try await ownSetControl.set.createSimulator(with: simulatorConfiguration)
    try await own.boot(FBSimulatorBootConfiguration(options: .tieToProcessLifecycle, environment: [:]))
    bootedSimulator = own
    simulator = own
  }

  override func tearDown() async throws {
    if let bootedSimulator, let control {
      try? await bootedSimulator.shutdown()
      try? await control.set.delete(bootedSimulator)
    }
    bootedSimulator = nil
    control = nil
    simulator = nil
  }

  /// Isolated from the default set, which holds the developer's own simulators.
  private static var fallbackDeviceSetPath: String {
    (NSTemporaryDirectory() as NSString).appendingPathComponent("FBSimulatorControlSmokeTests_CustomSet")
  }

  /// An iPhone configuration the host can actually create. The preferred model is tried
  /// first, then every other iPhone in the catalogue: naming one model and stopping there is
  /// how this suite's predecessor died, since a hardcoded model quietly stops being creatable
  /// as runtimes move on.
  private static func bootableiPhoneConfiguration() throws -> FBSimulatorConfiguration? {
    let base = try FBSimulatorConfiguration.defaultConfiguration()
    let catalogueiPhones = FBiOSTargetConfiguration.nameToDevice
      .filter { $0.value.family == .familyiPhone }
      .keys
      .sorted { $0.rawValue < $1.rawValue }
    for model in [FBDeviceModel.modeliPhone16] + catalogueiPhones {
      let configuration = base.withDeviceModel(model)
      if (try? configuration.checkRuntimeRequirements()) != nil {
        return configuration
      }
    }
    return nil
  }

  /// Some harnesses lease simulators whose host does not run `SimLaunchHostService`, so any
  /// command that spawns a service inside the guest fails with a `SimLaunchHostService`
  /// request error surfacing as an unacceptable exit code. That is a property of the lease,
  /// not of the code under test, so it skips rather than fails.
  func skippingIfGuestServiceSpawnUnavailable<T>(_ body: () async throws -> T) async throws -> T {
    do {
      return try await body()
    } catch {
      let description = String(describing: error)
      if description.contains("SimLaunchHostService.RequestError") || description.contains("Exit Code 149 is not acceptable") {
        throw XCTSkip("This simulator's host does not run SimLaunchHostService; cannot spawn services in the guest: \(description)")
      }
      throw error
    }
  }
}
