/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

/// Helper to call [FBFuture futureWithFutures:] which is NS_SWIFT_UNAVAILABLE.
private func combineFutures(_ futures: [FBFuture<AnyObject>]) -> FBFuture<AnyObject> {
  let sel = NSSelectorFromString("futureWithFutures:")
  let method = FBFuture<AnyObject>.method(for: sel)
  typealias Signature = @convention(c) (AnyObject, Selector, NSArray) -> FBFuture<AnyObject>
  let impl = unsafeBitCast(method, to: Signature.self)
  return impl(FBFuture<AnyObject>.self, sel, futures as NSArray)
}

@objc(FBDefaultsModificationStrategy)
public class FBDefaultsModificationStrategy: NSObject {

  // MARK: - Properties

  fileprivate let simulator: FBSimulator

  // MARK: - Initializers

  @objc(strategyWithSimulator:)
  public class func strategy(with simulator: FBSimulator) -> Self {
    return self.init(simulator: simulator)
  }

  required init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - Public Methods

  @objc
  public func modifyDefaults(inDomainOrPath domainOrPath: String?, defaults: [String: Any]) -> FBFuture<NSNull> {
    let file = (simulator.auxillaryDirectory as NSString).appendingPathComponent("temporary.plist")
    let dirPath = (file as NSString).deletingLastPathComponent

    do {
      try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true, attributes: nil)
    } catch {
      return
        FBSimulatorError
        .describe("Could not create intermediate directories for temporary plist \(file)")
        .caused(by: error as NSError)
        .failFuture() as! FBFuture<NSNull>
    }

    if !(defaults as NSDictionary).write(toFile: file, atomically: true) {
      return
        FBSimulatorError
        .describe("Failed to write out defaults to temporary file \(file)")
        .failFuture() as! FBFuture<NSNull>
    }

    // Build the arguments
    var arguments = ["import"]
    if let domainOrPath = domainOrPath {
      arguments.append(domainOrPath)
    }
    arguments.append(file)

    return performDefaultsCommand(withArguments: arguments).mapReplace(NSNull()) as! FBFuture<NSNull>
  }

  // MARK: - Internal Methods

  fileprivate func setDefault(inDomain domain: String, key: String, value: String, type: String?) -> FBFuture<NSNull> {
    return performDefaultsCommand(withArguments: [
      "write",
      domain,
      key,
      "-\(type ?? "string")",
      value,
    ]).mapReplace(NSNull()) as! FBFuture<NSNull>
  }

  fileprivate func getDefault(inDomain domain: String, key: String) -> FBFuture<NSString> {
    return performDefaultsCommand(withArguments: [
      "read",
      domain,
      key,
    ])
  }

  fileprivate func performDefaultsCommand(withArguments arguments: [String]) -> FBFuture<NSString> {
    // Make the Launch Config
    let configuration = FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>(
      launchPath: defaultsBinary,
      arguments: arguments,
      environment: [:],
      io: FBProcessIO.outputToDevNull(),
      mode: .default
    )

    // Run the defaults command.
    return
      (unsafeBitCast(
        FBProcessSpawnCommandHelpers.launchConsumingStdout(configuration, withCommands: simulator),
        to: FBFuture<AnyObject>.self
      )
      .onQueue(
        simulator.asyncQueue,
        map: { (output: Any) -> AnyObject in
          let str = output as! NSString
          return str.trimmingCharacters(in: .newlines) as NSString
        })) as! FBFuture<NSString>
  }

  fileprivate func amendRelativeTo(path relativePath: String, defaults: [String: Any], managingService serviceName: String) -> FBFuture<NSNull> {
    let simulator = self.simulator
    let state = simulator.state
    if state != .booted && state != .shutdown {
      return
        FBSimulatorError
        .describe("Cannot amend a plist when the Simulator state is \(FBiOSTargetStateStringFromState(state)), should be \(FBiOSTargetStateString.shutdown) or \(FBiOSTargetStateString.booted)")
        .failFuture() as! FBFuture<NSNull>
    }

    // Stop the service, if booted.
    let stopFuture: FBFuture<NSNull> =
      state == .booted
      ? simulator.stopService(withName: serviceName).mapReplace(NSNull()) as! FBFuture<NSNull>
      : FBFuture<NSNull>.empty()

    // The path to amend.
    let fullPath = (simulator.dataDirectory! as NSString).appendingPathComponent(relativePath)

    return
      (unsafeBitCast(stopFuture, to: FBFuture<AnyObject>.self)
      .onQueue(
        simulator.workQueue,
        fmap: { [weak self] (_: Any) -> FBFuture<AnyObject> in
          guard let self = self else {
            return FBFuture(result: NSNull())
          }
          return unsafeBitCast(self.modifyDefaults(inDomainOrPath: fullPath, defaults: defaults), to: FBFuture<AnyObject>.self)
        }
      )
      .onQueue(
        simulator.workQueue,
        fmap: { (_: Any) -> FBFuture<AnyObject> in
          // Re-start the Service if booted.
          if state == .booted {
            return simulator.startService(withName: serviceName).mapReplace(NSNull())
          }
          return FBFuture(result: NSNull())
        })) as! FBFuture<NSNull>
  }

  // MARK: - Private

  private var defaultsBinary: String {
    let path =
      ((FBSimDeviceWrapper.runtimeRoot(forDevice: simulator.device)! as NSString)
      .appendingPathComponent("usr") as NSString)
      .appendingPathComponent("bin") as NSString
    let fullPath = path.appendingPathComponent("defaults")
    do {
      let binary = try FBBinaryDescriptor.binary(withPath: fullPath)
      return binary.path
    } catch {
      fatalError("Could not locate defaults at expected location '\(fullPath)', error \(error)")
    }
  }
}

// MARK: - FBPreferenceModificationStrategy

@objc(FBPreferenceModificationStrategy)
public class FBPreferenceModificationStrategy: FBDefaultsModificationStrategy {

  private static let appleGlobalDomain = "Apple Global Domain"

  @objc
  public func setPreference(_ name: String, value: String, type: String?, domain: String?) -> FBFuture<NSNull> {
    let effectiveDomain = domain ?? FBPreferenceModificationStrategy.appleGlobalDomain
    return setDefault(inDomain: effectiveDomain, key: name, value: value, type: type)
  }

  @objc
  public func getCurrentPreference(_ name: String, domain: String?) -> FBFuture<NSString> {
    let effectiveDomain = domain ?? FBPreferenceModificationStrategy.appleGlobalDomain
    return getDefault(inDomain: effectiveDomain, key: name)
  }
}

// MARK: - FBLocationServicesModificationStrategy

@objc(FBLocationServicesModificationStrategy)
public class FBLocationServicesModificationStrategy: FBDefaultsModificationStrategy {

  @objc
  public func approveLocationServices(forBundleIDs bundleIDs: [String]) -> FBFuture<NSNull> {
    var defaults: [String: Any] = [:]
    for bundleID in bundleIDs {
      defaults[bundleID] =
        [
          "Whitelisted": false,
          "BundleId": bundleID,
          "SupportedAuthorizationMask": 3,
          "Authorization": 2,
          "Authorized": true,
          "Executable": "",
          "Registered": "",
        ] as [String: Any]
    }

    return amendRelativeTo(
      path: "Library/Caches/locationd/clients.plist",
      defaults: defaults,
      managingService: "locationd"
    )
  }

  @objc
  public func revokeLocationServices(forBundleIDs bundleIDs: [String]) -> FBFuture<NSNull> {
    let state = simulator.state
    if state != .booted && state != .shutdown {
      return
        FBSimulatorError
        .describe("Cannot modify a plist when the Simulator state is \(FBiOSTargetStateStringFromState(state)), should be \(FBiOSTargetStateString.shutdown) or \(FBiOSTargetStateString.booted)")
        .failFuture() as! FBFuture<NSNull>
    }

    let serviceName = "locationd"

    // Stop the service, if booted.
    let stopFuture: FBFuture<NSNull> =
      state == .booted
      ? simulator.stopService(withName: serviceName).mapReplace(NSNull()) as! FBFuture<NSNull>
      : FBFuture<NSNull>.empty()

    let path = (simulator.dataDirectory! as NSString)
      .appendingPathComponent("Library/Caches/locationd/clients.plist")
    let futures: [FBFuture<AnyObject>] = bundleIDs.map { bundleID in
      unsafeBitCast(
        self.performDefaultsCommand(withArguments: ["delete", path, bundleID]),
        to: FBFuture<AnyObject>.self)
    }

    return
      (unsafeBitCast(stopFuture, to: FBFuture<AnyObject>.self)
      .onQueue(
        simulator.workQueue,
        fmap: { (_: Any) -> FBFuture<AnyObject> in
          return combineFutures(futures).mapReplace(NSNull())
        }
      )
      .onQueue(
        simulator.workQueue,
        fmap: { [weak self] (_: Any) -> FBFuture<AnyObject> in
          guard let self = self else {
            return FBFuture(result: NSNull())
          }
          // Re-start the Service if booted.
          if state == .booted {
            return self.simulator.startService(withName: serviceName).mapReplace(NSNull())
          }
          return FBFuture(result: NSNull())
        })) as! FBFuture<NSNull>
  }
}
