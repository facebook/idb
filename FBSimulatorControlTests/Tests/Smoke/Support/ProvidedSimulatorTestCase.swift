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

private let DeviceUDIDEnvKey = "DEVICE_UDID"
private let DeviceSetPathEnvKey = "DEVICE_SET_PATH"

private struct ProvidedSimulatorError: Error, LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

/// A test case for tests that need a booted simulator but do not own one.
///
/// The simulator comes from the environment — a CI job, a developer's shell, an execution harness —
/// and is never created here: booting is the Boot suite's job, where the lifecycle is the thing
/// under test. A harness supplies one either by naming it in `DEVICE_UDID` (with `DEVICE_SET_PATH`
/// naming its device set) or by leaving exactly one booted simulator in that set.
///
/// It is acquired once and reused by every case in the bundle. Acquiring is the expensive part of
/// a smoke test — `setUp` runs per case, and a simulator resolved per case would multiply that cost
/// by the number of cases for no added coverage.
///
/// The simulator is a leased resource: tests restore anything they mutate, and nothing here boots,
/// shuts down, erases or deletes it.
///
/// It is not handed to a test until it has *finished* booting. `booted` is reported the moment the
/// boot is underway, and a simulator still on its way up has no SpringBoard and no application able
/// to answer: work taken against it does not fail, it waits — turning a missing precondition into
/// minutes of unexplained latency, or a timeout blamed on whatever happened to run first. Every
/// harness is expected to hand over a simulator in a good state; this verifies the ones that do and
/// waits for the ones that do not.
class ProvidedSimulatorTestCase: XCTestCase {

  /// The one acquisition for the whole bundle. Memoized as a `Task` so cases share the work rather
  /// than the result of a race; XCTest runs cases serially, so this is only ever awaited in turn.
  private nonisolated(unsafe) static var acquisition: Task<FBSimulator, Error>?

  private(set) var simulator: FBSimulator!

  override func setUp() async throws {
    continueAfterFailure = false
    simulator = try await Self.acquireSimulator()
  }

  private static func acquireSimulator() async throws -> FBSimulator {
    if let acquisition {
      return try await acquisition.value
    }
    let task = Task<FBSimulator, Error> {
      let simulator = try resolveProvidedSimulator()
      try await waitUntilBootCompleted(simulator)
      return simulator
    }
    acquisition = task
    do {
      return try await task.value
    } catch {
      // A failed acquisition is not memoized as a success; the next case re-reports it identically.
      acquisition = nil
      throw error
    }
  }

  /// Finds the simulator the environment provided, or skips: nothing supplied one, and this suite
  /// does not boot.
  private static func resolveProvidedSimulator() throws -> FBSimulator {
    try FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(FBControlCoreGlobalConfiguration.defaultLogger)
    let environment = ProcessInfo.processInfo.environment
    let noLogger: (any FBControlCoreLogger)? = nil
    let configuration = FBSimulatorControlConfiguration(
      deviceSetPath: environment[DeviceSetPathEnvKey],
      logger: noLogger)
    let control = try SimulatorControlBootstrap.withConfiguration(configuration)

    if let udid = environment[DeviceUDIDEnvKey] {
      guard let simulator = control.set.simulator(withUDID: udid) else {
        throw ProvidedSimulatorError(message: "The provided simulator \(udid) is not present in the device set")
      }
      guard simulator.state == .booted else {
        throw ProvidedSimulatorError(message: "The provided simulator \(udid) must already be booted; it is \(simulator.state)")
      }
      return simulator
    }

    let booted = control.set.allSimulators.filter { $0.state == .booted }
    guard booted.count == 1 else {
      let reason =
        booted.isEmpty
        ? "no booted simulator in the device set"
        : "several booted simulators in the device set (\(booted.map(\.udid).joined(separator: ", ")))"
      throw XCTSkip(
        "No simulator was provided: \(reason). This suite consumes a booted simulator from its "
          + "environment and does not boot one — boot exactly one, or name one with \(DeviceUDIDEnvKey) "
          + "(and optionally \(DeviceSetPathEnvKey)).")
    }
    return booted[0]
  }

  /// Blocks until the simulator has finished booting, which is what boot verification waits on —
  /// `resolveState(.booted)` is not it, since `booted` is reported while the boot is still in
  /// progress. Booting applies that check to a simulator it has just booted itself; it applies just
  /// as well to one handed over by somebody else.
  ///
  /// The wait is unbounded, and the test's execution time allowance is what stops it: a harness
  /// that never finishes booting the simulator it promised is not something this can recover from.
  private static func waitUntilBootCompleted(_ simulator: FBSimulator) async throws {
    try await SimulatorBootVerificationStrategy.verifySimulatorIsBooted(simulator)
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
