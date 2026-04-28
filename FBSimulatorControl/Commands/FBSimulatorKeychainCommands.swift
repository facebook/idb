/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// swiftlint:disable force_cast

@objc public protocol FBSimulatorKeychainCommandsProtocol: NSObjectProtocol {
  func clearKeychain() -> FBFuture<NSNull>
}

@objc(FBSimulatorKeychainCommands)
public final class FBSimulatorKeychainCommands: NSObject, FBSimulatorKeychainCommandsProtocol, FBiOSTargetCommand {

  // MARK: - Constants

  private static let securitydServiceName = "com.apple.securityd"
  private static let securitydServiceStartupShutdownTimeout: TimeInterval = 10.0
  private static let keychainPathsToIgnoreSet: Set<String> = ["TrustStore.sqlite3"]

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorKeychainCommands {
    return FBSimulatorKeychainCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - FBSimulatorKeychainCommandsProtocol (legacy FBFuture entry point)

  @objc
  public func clearKeychain() -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await clearKeychainAsync()
      return NSNull()
    }
  }

  // MARK: - Async

  public func clearKeychainAsync() async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let serviceName = FBSimulatorKeychainCommands.securitydServiceName
    let timeout = FBSimulatorKeychainCommands.securitydServiceStartupShutdownTimeout

    if simulator.state == .booted {
      let stopFuture =
        simulator.stopService(withName: serviceName)
        .timeout(timeout, waitingFor: "\(serviceName) service to stop") as! FBFuture<NSString>
      _ = try await bridgeFBFuture(stopFuture)
    }

    try removeKeychainContents(logger: simulator.logger)

    if simulator.state == .booted {
      let startFuture =
        simulator.startService(withName: serviceName)
        .timeout(timeout, waitingFor: "\(serviceName) service to restart") as! FBFuture<NSString>
      _ = try await bridgeFBFuture(startFuture)
    }
  }

  // MARK: - Private

  private func removeKeychainContents(logger: (any FBControlCoreLogger)?) throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    guard let dataDirectory = simulator.dataDirectory else {
      throw FBSimulatorError.describe("Simulator has no data directory").build()
    }
    let keychainDirectory =
      ((dataDirectory as NSString)
      .appendingPathComponent("Library") as NSString)
      .appendingPathComponent("Keychains")

    var isDirectory: ObjCBool = false
    if !FileManager.default.fileExists(atPath: keychainDirectory, isDirectory: &isDirectory) {
      simulator.logger?.info().log("The keychain directory does not exist at '\(keychainDirectory)'")
      return
    }
    if !isDirectory.boolValue {
      throw
        FBSimulatorError
        .describe("Keychain path \(keychainDirectory) is not a directory")
        .build()
    }

    let paths = try FileManager.default.contentsOfDirectory(atPath: keychainDirectory)
    for path in paths {
      let fullPath = (keychainDirectory as NSString).appendingPathComponent(path)
      if FBSimulatorKeychainCommands.keychainPathsToIgnoreSet.contains((fullPath as NSString).lastPathComponent) {
        logger?.log("Not removing keychain at path \(fullPath)")
        continue
      }
      logger?.log("Removing keychain at path \(fullPath)")
      try FileManager.default.removeItem(atPath: fullPath)
    }
  }
}
