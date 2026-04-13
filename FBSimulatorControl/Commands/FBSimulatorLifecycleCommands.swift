// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import AppKit
@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

/// Helper to call [FBFuture futureWithFutures:] which is NS_SWIFT_UNAVAILABLE.
private func combineFutures(_ futures: [FBFuture<AnyObject>]) -> FBFuture<AnyObject> {
  let sel = NSSelectorFromString("futureWithFutures:")
  let method = FBFuture<AnyObject>.method(for: sel)
  typealias Signature = @convention(c) (AnyObject, Selector, NSArray) -> FBFuture<AnyObject>
  let impl = unsafeBitCast(method, to: Signature.self)
  return impl(FBFuture<AnyObject>.self, sel, futures as NSArray)
}

private let openURLRetries = 2

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

  // MARK: - Boot/Shutdown

  @objc
  public func boot(_ configuration: FBSimulatorBootConfiguration) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    return FBSimulatorBootStrategy.boot(simulator, with: configuration)
  }

  // MARK: - FBPowerCommands

  @objc
  public func shutdown() -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    return (simulator.set.shutdown(simulator) as FBFuture).mapReplace(NSNull()) as! FBFuture<NSNull>
  }

  @objc
  public func reboot() -> FBFuture<NSNull> {
    return
      (unsafeBitCast(shutdown(), to: FBFuture<AnyObject>.self)
      .onQueue(
        simulator!.workQueue,
        fmap: { [weak self] (_: Any) -> FBFuture<AnyObject> in
          guard let self else {
            return FBSimulatorError.describe("Simulator deallocated").failFuture()
          }
          return unsafeBitCast(self.boot(FBSimulatorBootConfiguration.default), to: FBFuture<AnyObject>.self)
        })) as! FBFuture<NSNull>
  }

  // MARK: - Erase

  @objc
  public func erase() -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    return (simulator.set.erase(simulator) as FBFuture).mapReplace(NSNull()) as! FBFuture<NSNull>
  }

  // MARK: - States

  @objc
  public func resolve(_ state: FBiOSTargetState) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    return FBiOSTargetResolveState(simulator, state)
  }

  @objc
  public func resolveLeavesState(_ state: FBiOSTargetState) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    return FBCoreSimulatorNotifier.resolveLeavesState(state, for: simulator.device)
  }

  // MARK: - Focus

  @objc
  public func focus() -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    // We cannot 'focus' a SimulatorApp for the non-default device set.
    if let deviceSetPath = simulator.customDeviceSetPath {
      return FBSimulatorError.describe("Focusing on the Simulator App for a simulator in a custom device set (\(deviceSetPath)) is not supported")
        .failFuture() as! FBFuture<NSNull>
    }

    // Find the running instances of SimulatorApp.
    let apps = NSWorkspace.shared.runningApplications
    let simulatorApps = apps.filter { $0.bundleIdentifier == "com.apple.iphonesimulator" }

    // If we have no SimulatorApp running then we can instead launch one in a focused state
    if simulatorApps.isEmpty {
      return FBSimulatorLifecycleCommands.launchSimulatorApplicationForDefaultDeviceSet()
    }

    // Multiple apps, we don't know which to select.
    if simulatorApps.count > 1 {
      return FBSimulatorError.describe("More than one SimulatorApp \(FBCollectionInformation.oneLineDescription(from: simulatorApps)) running, focus is ambiguous")
        .failFuture() as! FBFuture<NSNull>
    }

    // Otherwise we have a single Simulator App to activate.
    let simulatorApp = simulatorApps.first!
    if !simulatorApp.activate(options: .activateIgnoringOtherApps) {
      return FBSimulatorError.describe("Failed to focus \(simulatorApp)")
        .failFuture() as! FBFuture<NSNull>
    }

    return FBFuture<NSNull>.empty()
  }

  private class func launchSimulatorApplicationForDefaultDeviceSet() -> FBFuture<NSNull> {
    let applicationBundle = FBXcodeConfiguration.simulatorApp
    let applicationURL = URL(fileURLWithPath: applicationBundle.path)
    let future = FBMutableFuture<NSNull>()
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { _, error in
      if let error {
        future.resolveWithError(error)
      } else {
        future.resolve(withResult: NSNull())
      }
    }
    return unsafeBitCast(future, to: FBFuture<NSNull>.self)
  }

  // MARK: - Connection

  @objc
  public func disconnect(withTimeout timeout: TimeInterval, logger: (any FBControlCoreLogger)?) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    let date = Date()
    return
      (unsafeBitCast(terminateConnections(), to: FBFuture<AnyObject>.self)
      .timeout(timeout, waitingFor: "Simulator connections to teardown")
      .onQueue(
        simulator.workQueue,
        map: { (_: Any) -> NSNull in
          logger?.debug().log("Simulator connections torn down in \(Date().timeIntervalSince(date)) seconds")
          return NSNull()
        })) as! FBFuture<NSNull>
  }

  private func terminateConnections() -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBFuture<NSNull>.empty()
    }
    let hidFuture: FBFuture<AnyObject> =
      hid != nil
      ? unsafeBitCast(hid!.disconnect(), to: FBFuture<AnyObject>.self)
      : unsafeBitCast(FBFuture<NSNull>.empty(), to: FBFuture<AnyObject>.self)
    let bridgeFuture: FBFuture<AnyObject> =
      bridge != nil
      ? unsafeBitCast(bridge!.disconnect(), to: FBFuture<AnyObject>.self)
      : unsafeBitCast(FBFuture<NSNull>.empty(), to: FBFuture<AnyObject>.self)

    return
      (combineFutures([hidFuture, bridgeFuture])
      .onQueue(
        simulator.workQueue,
        chain: { [weak self] (_: FBFuture<AnyObject>) -> FBFuture<AnyObject> in
          self?.hid = nil
          self?.bridge = nil
          return unsafeBitCast(FBFuture<NSNull>.empty(), to: FBFuture<AnyObject>.self)
        })) as! FBFuture<NSNull>
  }

  // MARK: - Bridge

  @objc
  public func connectToBridge() -> FBFuture<FBSimulatorBridge> {
    if let bridge = self.bridge {
      return FBFuture(result: bridge)
    }
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<FBSimulatorBridge>
    }
    return (FBSimulatorBridge.bridge(for: simulator) as FBFuture)
      .onQueue(
        simulator.workQueue,
        map: { [weak self] (bridge: Any) -> FBSimulatorBridge in
          let bridge = bridge as! FBSimulatorBridge
          self?.bridge = bridge
          return bridge
        }) as! FBFuture<FBSimulatorBridge>
  }

  // MARK: - Framebuffer

  @objc
  public func connectToFramebuffer() -> FBFuture<FBFramebuffer> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<FBFramebuffer>
    }
    return FBFuture.onQueue(
      simulator.workQueue,
      resolve: {
        do {
          return FBFuture(result: try FBFramebuffer.mainScreenSurface(for: simulator, logger: simulator.logger!))
        } catch {
          return FBFuture(error: error)
        }
      })
  }

  // MARK: - HID

  @objc
  public func connectToHID() -> FBFuture<FBSimulatorHID> {
    if let hid = self.hid {
      return FBFuture(result: hid)
    }
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<FBSimulatorHID>
    }
    return (FBSimulatorHID.hid(for: simulator) as FBFuture)
      .onQueue(
        simulator.workQueue,
        map: { [weak self] (hid: Any) -> FBSimulatorHID in
          let hid = hid as! FBSimulatorHID
          self?.hid = hid
          return hid
        }) as! FBFuture<FBSimulatorHID>
  }

  // MARK: - URLs

  @objc
  public func open(_ url: URL) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBSimulatorError.describe("Simulator deallocated").failFuture() as! FBFuture<NSNull>
    }
    var lastError: AnyObject?
    for _ in 0...openURLRetries {
      lastError = nil
      if simulator.device.openURL(url, error: &lastError) {
        return FBFuture(result: NSNull())
      }
    }

    return FBSimulatorError.describe("Failed to open URL \(url) on simulator \(simulator)")
      .failFuture() as! FBFuture<NSNull>
  }
}
