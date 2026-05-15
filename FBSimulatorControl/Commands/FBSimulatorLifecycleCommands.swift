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

@objc public protocol FBSimulatorLifecycleCommandsProtocol: NSObjectProtocol, FBiOSTargetCommand, FBEraseCommands, FBPowerCommands {
  @objc(boot:)
  func boot(_ configuration: FBSimulatorBootConfiguration) -> FBFuture<NSNull>

  func focus() -> FBFuture<NSNull>

  @objc(disconnectWithTimeout:logger:)
  func disconnect(withTimeout timeout: TimeInterval, logger: (any FBControlCoreLogger)?) -> FBFuture<NSNull>

  func connectToFramebuffer() -> FBFuture<FBFramebuffer>

  func connectToHID() -> FBFuture<FBSimulatorHID>

  @objc(openURL:)
  func open(_ url: URL) -> FBFuture<NSNull>
}

// MARK: - FBSimulator+FBSimulatorLifecycleCommandsProtocol

extension FBSimulator: FBSimulatorLifecycleCommandsProtocol {

  // MARK: FBEraseCommands

  @objc public func erase() -> FBFuture<NSNull> {
    do {
      return try lifecycleCommands().erase()
    } catch {
      return FBFuture(error: error)
    }
  }

  // MARK: FBPowerCommands

  @objc public func shutdown() -> FBFuture<NSNull> {
    do {
      return try lifecycleCommands().shutdown()
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc public func reboot() -> FBFuture<NSNull> {
    do {
      return try lifecycleCommands().reboot()
    } catch {
      return FBFuture(error: error)
    }
  }

  // MARK: FBSimulatorLifecycleCommandsProtocol

  @objc(boot:)
  public func boot(_ configuration: FBSimulatorBootConfiguration) -> FBFuture<NSNull> {
    do {
      return try lifecycleCommands().boot(configuration)
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc public func focus() -> FBFuture<NSNull> {
    do {
      return try lifecycleCommands().focus()
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc(disconnectWithTimeout:logger:)
  public func disconnect(withTimeout timeout: TimeInterval, logger: (any FBControlCoreLogger)?) -> FBFuture<NSNull> {
    do {
      return try lifecycleCommands().disconnect(withTimeout: timeout, logger: logger)
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc public func connectToFramebuffer() -> FBFuture<FBFramebuffer> {
    do {
      return try lifecycleCommands().connectToFramebuffer()
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc public func connectToHID() -> FBFuture<FBSimulatorHID> {
    do {
      return try lifecycleCommands().connectToHID()
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc(openURL:)
  public func open(_ url: URL) -> FBFuture<NSNull> {
    do {
      return try lifecycleCommands().open(url)
    } catch {
      return FBFuture(error: error)
    }
  }
}

@objc(FBSimulatorLifecycleCommands)
public final class FBSimulatorLifecycleCommands: NSObject, FBiOSTargetCommand {

  // MARK: - Properties

  private weak var simulator: FBSimulator?
  private var hid: FBSimulatorHID?

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorLifecycleCommands {
    return FBSimulatorLifecycleCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - Boot/Shutdown (legacy FBFuture entry points)

  @objc
  public func boot(_ configuration: FBSimulatorBootConfiguration) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await bootAsync(configuration)
      return NSNull()
    }
  }

  @objc
  public func shutdown() -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await shutdownAsync()
      return NSNull()
    }
  }

  @objc
  public func reboot() -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await rebootAsync()
      return NSNull()
    }
  }

  @objc
  public func erase() -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await eraseAsync()
      return NSNull()
    }
  }

  @objc
  public func focus() -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await focusAsync()
      return NSNull()
    }
  }

  @objc
  public func disconnect(withTimeout timeout: TimeInterval, logger: (any FBControlCoreLogger)?) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await disconnectAsync(withTimeout: timeout, logger: logger)
      return NSNull()
    }
  }

  @objc
  public func connectToFramebuffer() -> FBFuture<FBFramebuffer> {
    fbFutureFromAsync { [self] in
      try await connectToFramebufferAsync()
    }
  }

  @objc
  public func connectToHID() -> FBFuture<FBSimulatorHID> {
    fbFutureFromAsync { [self] in
      try await connectToHIDAsync()
    }
  }

  @objc
  public func open(_ url: URL) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await openAsync(url)
      return NSNull()
    }
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

  fileprivate func eraseAsync() async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    try await FBSimulatorEraseStrategy.eraseAsync(simulator)
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
    // We cannot 'focus' a SimulatorApp for the non-default device set.
    if let deviceSetPath = simulator.customDeviceSetPath {
      throw FBSimulatorError.describe("Focusing on the Simulator App for a simulator in a custom device set (\(deviceSetPath)) is not supported").build()
    }

    // Find the running instances of SimulatorApp.
    let apps = NSWorkspace.shared.runningApplications
    let simulatorApps = apps.filter { $0.bundleIdentifier == "com.apple.iphonesimulator" }

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
    if let hid {
      try await bridgeFBFutureVoid(hid.disconnect())
    }
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
    let hid = try await bridgeFBFuture(FBSimulatorHID.hid(for: simulator) as FBFuture)
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

// MARK: - FBSimulator+AsyncLifecycleCommands

extension FBSimulator: AsyncLifecycleCommands {

  public func resolveState(_ state: FBiOSTargetState) async throws {
    try await lifecycleCommands().resolveStateAsync(state)
  }

  public func resolveLeavesState(_ state: FBiOSTargetState) async throws {
    try await lifecycleCommands().resolveLeavesStateAsync(state)
  }
}

// MARK: - FBSimulator+AsyncPowerCommands

extension FBSimulator: AsyncPowerCommands {

  public func shutdown() async throws {
    try await lifecycleCommands().shutdownAsync()
  }

  public func reboot() async throws {
    try await lifecycleCommands().rebootAsync()
  }
}

// MARK: - FBSimulator+AsyncEraseCommands

extension FBSimulator: AsyncEraseCommands {

  public func erase() async throws {
    try await lifecycleCommands().eraseAsync()
  }
}

// MARK: - FBSimulator+AsyncSimulatorLifecycleCommands

extension FBSimulator: AsyncSimulatorLifecycleCommands {

  public func focus() async throws {
    try await lifecycleCommands().focusAsync()
  }

  public func open(_ url: URL) async throws {
    try await lifecycleCommands().openAsync(url)
  }

  public func connectToHID() async throws -> FBSimulatorHID {
    try await lifecycleCommands().connectToHIDAsync()
  }
}
