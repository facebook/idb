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

// swiftlint:disable force_cast force_unwrapping

private let openURLRetries = 2

@objc(FBSimulatorLifecycleCommands)
public final class FBSimulatorLifecycleCommands: NSObject, FBiOSTargetCommand {

  // MARK: - Properties

  private weak var simulator: FBSimulator?
  private var hid: FBSimulatorHID?

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorLifecycleCommands {
    FBSimulatorLifecycleCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - Async

  fileprivate func bootAsync(_ configuration: FBSimulatorBootConfiguration) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    try await FBSimulatorBootStrategy.bootAsync(simulator, with: configuration)
  }

  fileprivate func shutdownAsync() async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    try await FBSimulatorShutdownStrategy.shutdownAsync(simulator)
  }

  fileprivate func rebootAsync() async throws {
    try await shutdownAsync()
    try await bootAsync(FBSimulatorBootConfiguration.default)
  }

  fileprivate func erase() async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    try await FBSimulatorEraseStrategy.erase(simulator)
  }

  fileprivate func resolveStateAsync(_ state: FBiOSTargetState) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    try await bridgeFBFutureVoid(FBiOSTargetResolveState(simulator, state))
  }

  fileprivate func resolveLeavesStateAsync(_ state: FBiOSTargetState) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    try await bridgeFBFutureVoid(FBCoreSimulatorNotifier.resolveLeavesState(state, for: simulator.device))
  }

  fileprivate func focusAsync() async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    // The Simulator host app (Simulator.app, or DeviceHub.app on Xcode 27+) only displays
    // simulators in the default device set, so 'focus' is unsupported for a custom device set.
    // This is also why Xcode parallel testing — which clones into a non-default device set — is
    // not visible in DeviceHub (Apple known issue 176809181).
    if let deviceSetPath = simulator.customDeviceSetPath {
      throw FBSimulatorError.describe("Focusing on the Simulator App for a simulator in a custom device set (\(deviceSetPath)) is not supported").build()
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
    if simulatorApps.isEmpty {
      try await FBSimulatorLifecycleCommands.launchSimulatorApplicationForDefaultDeviceSet()
      return
    }

    // Multiple apps, we don't know which to select.
    if simulatorApps.count > 1 {
      throw FBSimulatorError.describe("More than one SimulatorApp \(FBCollectionInformation.oneLineDescription(from: simulatorApps)) running, focus is ambiguous").build()
    }

    // Otherwise we have a single Simulator App to activate.
    let simulatorApp = simulatorApps.first!
    if !simulatorApp.activate(options: .activateIgnoringOtherApps) {
      throw FBSimulatorError.describe("Failed to focus \(simulatorApp)").build()
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

  fileprivate func disconnectAsync(withTimeout timeout: TimeInterval, logger: (any FBControlCoreLogger)?) async throws {
    guard self.simulator != nil else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let date = Date()
    let teardownFuture =
      fbFutureFromAsync { [self] in
        try await terminateConnectionsAsync()
        return NSNull()
      }
      .timeout(timeout, waitingFor: "Simulator connections to teardown") as! FBFuture<NSNull>
    try await bridgeFBFutureVoid(teardownFuture)
    logger?.debug().log("Simulator connections torn down in \(Date().timeIntervalSince(date)) seconds")
  }

  private func terminateConnectionsAsync() async throws {
    hid?.disconnect()
    self.hid = nil
  }

  fileprivate func connectToFramebufferAsync() async throws -> FBFramebuffer {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    return try FBFramebuffer.mainScreenSurface(for: simulator, logger: simulator.logger!)
  }

  fileprivate func connectToHIDAsync() async throws -> FBSimulatorHID {
    if let hid = self.hid {
      return hid
    }
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let hid = try FBSimulatorHID(for: simulator)
    self.hid = hid
    return hid
  }

  fileprivate func openAsync(_ url: URL) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
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
    _ = lastError
    throw FBSimulatorError.describe("Failed to open URL \(url) on simulator \(simulator)").build()
  }
}

// MARK: - FBSimulator+LifecycleCommands

extension FBSimulator: LifecycleCommands {

  public func resolveState(_ state: FBiOSTargetState) async throws {
    try await lifecycleCommands().resolveStateAsync(state)
  }

  public func resolveLeavesState(_ state: FBiOSTargetState) async throws {
    try await lifecycleCommands().resolveLeavesStateAsync(state)
  }
}

// MARK: - FBSimulator+PowerCommands

extension FBSimulator: PowerCommands {

  public func shutdown() async throws {
    try await lifecycleCommands().shutdownAsync()
  }

  public func reboot() async throws {
    try await lifecycleCommands().rebootAsync()
  }
}

// MARK: - FBSimulator+EraseCommands

extension FBSimulator: EraseCommands {

  public func erase() async throws {
    try await lifecycleCommands().erase()
  }
}

// MARK: - FBSimulator+SimulatorLifecycleCommands

extension FBSimulator: SimulatorLifecycleCommands {

  public func boot(_ configuration: FBSimulatorBootConfiguration) async throws {
    try await lifecycleCommands().bootAsync(configuration)
  }

  public func focus() async throws {
    try await lifecycleCommands().focusAsync()
  }

  public func disconnect(withTimeout timeout: TimeInterval, logger: (any FBControlCoreLogger)?) async throws {
    try await lifecycleCommands().disconnectAsync(withTimeout: timeout, logger: logger)
  }

  public func connectToFramebuffer() async throws -> FBFramebuffer {
    try await lifecycleCommands().connectToFramebufferAsync()
  }

  public func open(_ url: URL) async throws {
    try await lifecycleCommands().openAsync(url)
  }

  public func connectToHID() async throws -> FBSimulatorHID {
    try await lifecycleCommands().connectToHIDAsync()
  }
}
