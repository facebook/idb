/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

// swiftlint:disable force_unwrapping

public class FBDefaultsModificationStrategy: NSObject {

  // MARK: - Properties

  fileprivate let simulator: FBSimulator

  // MARK: - Initializers

  required init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - Public Methods

  public func modifyDefaults(inDomainOrPath domainOrPath: String?, defaults: [String: Any]) async throws {
    let file = (simulator.auxillaryDirectory as NSString).appendingPathComponent("temporary.plist")
    let dirPath = (file as NSString).deletingLastPathComponent

    do {
      try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true, attributes: nil)
    } catch {
      throw
        FBSimulatorError
        .describe("Could not create intermediate directories for temporary plist \(file)")
        .caused(by: error as NSError)
        .build()
    }

    if !(defaults as NSDictionary).write(toFile: file, atomically: true) {
      throw FBSimulatorError.describe("Failed to write out defaults to temporary file \(file)").build()
    }

    _ = try await run(.importPlist(domainOrPath: domainOrPath, file: file))
  }

  // MARK: - Internal Methods

  fileprivate func setDefault(inDomain domain: String, key: String, value: String, type: String?) async throws {
    _ = try await run(.write(domain: domain, key: key, type: type ?? "string", value: value))
  }

  fileprivate func getDefault(inDomain domain: String, key: String) async throws -> NSString {
    return try await run(.read(domain: domain, key: key))
  }

  // The closed set of `defaults` operations this strategy issues. Modelling them as an enum keeps argv
  // construction in one place and makes the operation set exhaustive, so a new operation cannot be
  // added without routing through `run`.
  enum Command {
    case read(domain: String, key: String)
    case write(domain: String, key: String, type: String, value: String)
    case importPlist(domainOrPath: String?, file: String)
    case delete(path: String, key: String)

    var arguments: [String] {
      switch self {
      case let .read(domain, key):
        return ["read", domain, key]
      case let .write(domain, key, type, value):
        return ["write", domain, key, "-\(type)", value]
      case let .importPlist(domainOrPath, file):
        var args = ["import"]
        if let domainOrPath {
          args.append(domainOrPath)
        }
        args.append(file)
        return args
      case let .delete(path, key):
        return ["delete", path, key]
      }
    }

    var exitCodePolicy: ExitCodePolicy {
      switch self {
      case .read, .delete:
        // `defaults` returns 1 for a missing key/domain (a benign optional read or idempotent delete)
        // and for a genuine failure alike, with no distinguishing code, so tolerate any non-zero.
        return .tolerateAny
      case .write, .importPlist:
        return .require([0])
      }
    }
  }

  fileprivate func run(_ command: Command) async throws -> NSString {
    let launchPath = defaultsBinary
    let output = try await simulator.launchProcessConsumingOutput(launchPath: launchPath, arguments: command.arguments)
    return try FBDefaultsModificationStrategy.stdout(orThrowFrom: output, command: command, logger: simulator.logger)
  }

  // Internal for unit-test coverage of the exit-code handling; see FBDefaultsModificationStrategyTests.
  static func stdout(orThrowFrom output: FBInSimulatorToolOutput, command: Command, logger: (any FBControlCoreLogger)?) throws -> NSString {
    if output.exitCode != 0 {
      let stderr = String(data: output.stderr, encoding: .utf8) ?? ""
      guard command.exitCodePolicy.accepts(output.exitCode) else {
        throw FBSimulatorError.describe("defaults \(command.arguments.joined(separator: " ")) failed with exit code \(output.exitCode): \(stderr)").build()
      }
      logger?.log("defaults \(command.arguments.joined(separator: " ")) exited with code \(output.exitCode): \(stderr)")
    }
    let stdout = String(data: output.stdout, encoding: .utf8) ?? ""
    return stdout.trimmingCharacters(in: .newlines) as NSString
  }

  fileprivate func amendRelativeTo(path relativePath: String, defaults: [String: Any], managingService serviceName: String) async throws {
    let state = simulator.state
    guard state == .booted || state == .shutdown else {
      throw
        FBSimulatorError
        .describe("Cannot amend a plist when the Simulator state is \(FBiOSTargetStateStringFromState(state)), should be \(FBiOSTargetStateString.shutdown) or \(FBiOSTargetStateString.booted)")
        .build()
    }

    // Stop the service while the plist is rewritten, restarting it afterwards if it was running.
    if state == .booted {
      _ = try await simulator.stopService(withName: serviceName)
    }
    let fullPath = (simulator.dataDirectory! as NSString).appendingPathComponent(relativePath)
    try await modifyDefaults(inDomainOrPath: fullPath, defaults: defaults)
    if state == .booted {
      _ = try await simulator.startService(withName: serviceName)
    }
  }

  // MARK: - Private

  private var defaultsBinary: String {
    let path =
      ((simulator.device.runtime.root! as NSString)
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

public class FBPreferenceModificationStrategy: FBDefaultsModificationStrategy {

  private static let appleGlobalDomain = "Apple Global Domain"

  public func setPreference(_ name: String, value: String, type: String?, domain: String?) async throws {
    let effectiveDomain = domain ?? FBPreferenceModificationStrategy.appleGlobalDomain
    try await setDefault(inDomain: effectiveDomain, key: name, value: value, type: type)
  }

  public func getCurrentPreference(_ name: String, domain: String?) async throws -> String {
    let effectiveDomain = domain ?? FBPreferenceModificationStrategy.appleGlobalDomain
    return try await getDefault(inDomain: effectiveDomain, key: name) as String
  }
}

// MARK: - FBLocationServicesModificationStrategy

public class FBLocationServicesModificationStrategy: FBDefaultsModificationStrategy {

  public func approveLocationServices(forBundleIDs bundleIDs: [String]) async throws {
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

    try await amendRelativeTo(
      path: "Library/Caches/locationd/clients.plist",
      defaults: defaults,
      managingService: "locationd"
    )
  }

  public func revokeLocationServices(forBundleIDs bundleIDs: [String]) async throws {
    let state = simulator.state
    guard state == .booted || state == .shutdown else {
      throw
        FBSimulatorError
        .describe("Cannot modify a plist when the Simulator state is \(FBiOSTargetStateStringFromState(state)), should be \(FBiOSTargetStateString.shutdown) or \(FBiOSTargetStateString.booted)")
        .build()
    }

    let serviceName = "locationd"
    if state == .booted {
      _ = try await simulator.stopService(withName: serviceName)
    }

    let path = (simulator.dataDirectory! as NSString)
      .appendingPathComponent("Library/Caches/locationd/clients.plist")
    // Delete sequentially: every delete is a read-modify-write of the same clients.plist, so running
    // them concurrently races and can drop entries when revoking several bundle IDs at once.
    for bundleID in bundleIDs {
      _ = try await run(.delete(path: path, key: bundleID))
    }

    if state == .booted {
      _ = try await simulator.startService(withName: serviceName)
    }
  }
}
