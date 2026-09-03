/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AppKit
@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

private let openURLRetries = 2

/// The ways simulator lifecycle operations can fail, as data rather than assembled strings.
public enum FBSimulatorLifecycleError: Error {
  case focusUnsupportedForCustomDeviceSet(deviceSetPath: String)
  case focusAmbiguous(runningApplications: String)
  case focusFailed(applicationDescription: String)
  case openURLFailed(url: URL, simulatorDescription: String, underlying: Error?)
}

extension FBSimulatorLifecycleError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .focusUnsupportedForCustomDeviceSet(deviceSetPath):
      return "Focusing on the Simulator App for a simulator in a custom device set (\(deviceSetPath)) is not supported"
    case let .focusAmbiguous(runningApplications):
      return "More than one SimulatorApp \(runningApplications) running, focus is ambiguous"
    case let .focusFailed(applicationDescription):
      return "Failed to focus \(applicationDescription)"
    case let .openURLFailed(url, simulatorDescription, _):
      return "Failed to open URL \(url) on simulator \(simulatorDescription)"
    }
  }
}

public final class FBSimulatorLifecycleCommands {

  // MARK: - Properties

  private weak var simulator: FBSimulator?
  private var hid: FBSimulatorHID?

  // MARK: - Initializers

  public class func commands(with simulator: FBSimulator) -> FBSimulatorLifecycleCommands {
    FBSimulatorLifecycleCommands(simulator: simulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  // MARK: - Async

  fileprivate func boot(_ configuration: FBSimulatorBootConfiguration) async throws {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    try await FBSimulatorBootStrategy.boot(simulator, with: configuration)
  }

  fileprivate func shutdown() async throws {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    try await FBSimulatorShutdownStrategy.shutdown(simulator)
  }

  fileprivate func reboot() async throws {
    try await shutdown()
    try await boot(FBSimulatorBootConfiguration.default)
  }

  fileprivate func erase() async throws {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    try await FBSimulatorEraseStrategy.erase(simulator)
  }

  fileprivate func resolveStateAsync(_ state: FBiOSTargetState) async throws {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    try await FBiOSTargetResolveState(simulator, state)
  }

  fileprivate func resolveLeavesStateAsync(_ state: FBiOSTargetState) async throws {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    try await bridgeFBFutureVoid(FBCoreSimulatorNotifier.resolveLeavesState(state, for: simulator.device))
  }

  fileprivate func focus() async throws {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    // The Simulator host app (Simulator.app, or DeviceHub.app on Xcode 27+) only displays
    // simulators in the default device set, so 'focus' is unsupported for a custom device set.
    // This is also why Xcode parallel testing — which clones into a non-default device set — is
    // not visible in DeviceHub (Apple known issue 176809181).
    if let deviceSetPath = simulator.customDeviceSetPath {
      throw FBSimulatorLifecycleError.focusUnsupportedForCustomDeviceSet(deviceSetPath: deviceSetPath)
    }

    // Find the running instances of the Simulator host app. Xcode 27 renamed Simulator.app
    // (com.apple.iphonesimulator) to DeviceHub.app (com.apple.dt.Devices); match either.
    let apps = NSWorkspace.shared.runningApplications
    let simulatorAppBundleIDs: Set<String> = ["com.apple.iphonesimulator", "com.apple.dt.Devices"]
    let simulatorApps = apps.filter { app in
      guard let bundleIdentifier = app.bundleIdentifier else { return false }
      return simulatorAppBundleIDs.contains(bundleIdentifier)
    }

    // If we have no SimulatorApp running then we can instead launch one in a focused state
    guard let simulatorApp = simulatorApps.first else {
      try await FBSimulatorLifecycleCommands.launchSimulatorApplicationForDefaultDeviceSet()
      return
    }

    // Multiple apps, we don't know which to select.
    if simulatorApps.count > 1 {
      throw FBSimulatorLifecycleError.focusAmbiguous(runningApplications: FBCollectionInformation.oneLineDescription(from: simulatorApps))
    }

    // Otherwise we have a single Simulator App to activate.
    if !simulatorApp.activate() {
      throw FBSimulatorLifecycleError.focusFailed(applicationDescription: String(describing: simulatorApp))
    }
  }

  private class func launchSimulatorApplicationForDefaultDeviceSet() async throws {
    let applicationBundle = FBXcodeConfiguration.simulatorApp
    let applicationURL = URL(fileURLWithPath: applicationBundle.path)
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { _, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }

  fileprivate func disconnect(withTimeout timeout: TimeInterval, logger: (any FBControlCoreLogger)?) async throws {
    guard self.simulator != nil else {
      throw FBWeakTargetError.simulator
    }
    let date = Date()
    let teardownFuture =
      fbFutureFromAsync { [self] in
        try await terminateConnections()
        return NSNull()
      }
      .timeout(timeout, waitingFor: "Simulator connections to teardown")
      .retyped(FBFuture<NSNull>.self)
    try await bridgeFBFutureVoid(teardownFuture)
    logger?.debug().log("Simulator connections torn down in \(Date().timeIntervalSince(date)) seconds")
  }

  private func terminateConnections() async throws {
    hid?.disconnect()
    self.hid = nil
  }

  fileprivate func connectToFramebuffer() async throws -> FBFramebuffer {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    return try FBFramebuffer.mainScreenSurface(for: simulator, logger: simulator.logger)
  }

  fileprivate func connectToHID() async throws -> FBSimulatorHID {
    if let hid = self.hid {
      return hid
    }
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    let hid = try FBSimulatorHID(for: simulator)
    self.hid = hid
    return hid
  }

  fileprivate func open(_ url: URL) async throws {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    var lastError: NSError?
    for _ in 0...openURLRetries {
      lastError = nil
      do {
        try simulator.device.open(url)
        return
      } catch {
        lastError = error as NSError
      }
    }
    throw FBSimulatorLifecycleError.openURLFailed(url: url, simulatorDescription: String(describing: simulator), underlying: lastError)
  }
}

// MARK: - FBSimulator+LifecycleCommands

extension FBSimulator: LifecycleCommands {

  public func resolveState(_ state: FBiOSTargetState) async throws {
    try await lifecycle.resolveStateAsync(state)
  }

  public func resolveLeavesState(_ state: FBiOSTargetState) async throws {
    try await lifecycle.resolveLeavesStateAsync(state)
  }
}

// MARK: - FBSimulator+PowerCommands

extension FBSimulator: PowerCommands {

  public func shutdown() async throws {
    try await lifecycle.shutdown()
  }

  public func reboot() async throws {
    try await lifecycle.reboot()
  }
}

// MARK: - FBSimulator+EraseCommands

extension FBSimulator: EraseCommands {

  public func erase() async throws {
    try await lifecycle.erase()
  }
}

// MARK: - FBSimulator+SimulatorLifecycleCommands

extension FBSimulator: SimulatorLifecycleCommands {

  public func boot(_ configuration: FBSimulatorBootConfiguration) async throws {
    try await lifecycle.boot(configuration)
  }

  public func focus() async throws {
    try await lifecycle.focus()
  }

  public func disconnect(withTimeout timeout: TimeInterval, logger: (any FBControlCoreLogger)?) async throws {
    try await lifecycle.disconnect(withTimeout: timeout, logger: logger)
  }

  public func connectToFramebuffer() async throws -> FBFramebuffer {
    try await lifecycle.connectToFramebuffer()
  }

  public func open(_ url: URL) async throws {
    try await lifecycle.open(url)
  }

  public func connectToHID() async throws -> FBSimulatorHID {
    try await lifecycle.connectToHID()
  }
}
