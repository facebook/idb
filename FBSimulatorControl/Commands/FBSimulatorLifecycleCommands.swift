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

@objc public protocol FBSimulatorLifecycleCommandsProtocol: NSObjectProtocol, FBiOSTargetCommand, FBEraseCommands, FBPowerCommands, FBLifecycleCommands {
  @objc(boot:)
  func boot(_ configuration: FBSimulatorBootConfiguration) -> FBFuture<NSNull>

  func focus() -> FBFuture<NSNull>

  @objc(disconnectWithTimeout:logger:)
  func disconnect(withTimeout timeout: TimeInterval, logger: (any FBControlCoreLogger)?) -> FBFuture<NSNull>

  func connectToBridge() -> FBFuture<FBSimulatorBridge>

  func connectToFramebuffer() -> FBFuture<FBFramebuffer>

  func connectToHID() -> FBFuture<FBSimulatorHID>

  @objc(openURL:)
  func open(_ url: URL) -> FBFuture<NSNull>
}

@objc(FBSimulatorLifecycleCommands)
public final class FBSimulatorLifecycleCommands: NSObject, FBSimulatorLifecycleCommandsProtocol {

  // MARK: - Properties

  private weak var simulator: FBSimulator?
  private var hid: FBSimulatorHID?
  private var bridge: FBSimulatorBridge?

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

  @objc(resolveState:)
  public func resolveState(_ state: FBiOSTargetState) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await resolveStateAsync(state)
      return NSNull()
    }
  }

  @objc
  public func resolveLeavesState(_ state: FBiOSTargetState) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await resolveLeavesStateAsync(state)
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
  public func connectToBridge() -> FBFuture<FBSimulatorBridge> {
    fbFutureFromAsync { [self] in
      try await connectToBridgeAsync()
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
    try await bridgeFBFutureVoid(FBSimulatorBootStrategy.boot(simulator, with: configuration))
  }

  fileprivate func shutdownAsync() async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    _ = try await bridgeFBFuture(simulator.set.shutdown(simulator) as FBFuture)
  }

  fileprivate func rebootAsync() async throws {
    try await shutdownAsync()
    try await bootAsync(FBSimulatorBootConfiguration.default)
  }

  fileprivate func eraseAsync() async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    _ = try await bridgeFBFuture(simulator.set.erase(simulator) as FBFuture)
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
    if let bridge {
      try await bridgeFBFutureVoid(bridge.disconnect())
    }
    self.hid = nil
    self.bridge = nil
  }

  fileprivate func connectToBridgeAsync() async throws -> FBSimulatorBridge {
    if let bridge = self.bridge {
      return bridge
    }
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let bridge = try await bridgeFBFuture(FBSimulatorBridge.bridge(for: simulator) as FBFuture)
    self.bridge = bridge
    return bridge
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
    var lastError: AnyObject?
    for _ in 0...openURLRetries {
      lastError = nil
      if simulator.device.openURL(url, error: &lastError) {
        return
      }
    }
    _ = lastError
    throw FBSimulatorError.describe("Failed to open URL \(url) on simulator \(simulator)").build()
  }
}

// MARK: - AsyncPowerCommands

extension FBSimulatorLifecycleCommands: AsyncPowerCommands {

  public func shutdown() async throws {
    try await shutdownAsync()
  }

  public func reboot() async throws {
    try await rebootAsync()
  }
}

// MARK: - AsyncEraseCommands

extension FBSimulatorLifecycleCommands: AsyncEraseCommands {

  public func erase() async throws {
    try await eraseAsync()
  }
}

// MARK: - AsyncLifecycleCommands

extension FBSimulatorLifecycleCommands: AsyncLifecycleCommands {

  public func resolveState(_ state: FBiOSTargetState) async throws {
    try await resolveStateAsync(state)
  }

  public func resolveLeavesState(_ state: FBiOSTargetState) async throws {
    try await resolveLeavesStateAsync(state)
  }
}

// MARK: - AsyncSimulatorLifecycleCommands

extension FBSimulatorLifecycleCommands: AsyncSimulatorLifecycleCommands {

  public func focus() async throws {
    try await focusAsync()
  }

  public func open(_ url: URL) async throws {
    try await openAsync(url)
  }

  public func connectToHID() async throws -> FBSimulatorHID {
    return try await connectToHIDAsync()
  }
}
