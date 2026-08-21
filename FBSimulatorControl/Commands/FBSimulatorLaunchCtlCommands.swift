/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

// swiftlint:disable force_try

public final class FBSimulatorLaunchCtlCommands: NSObject {

  // MARK: - Properties

  private let simulator: FBSimulator
  private let launchctlLaunchPath: String

  // MARK: - Initializers

  private class func launchCtlLaunchPath(for simulator: FBSimulator) throws -> String {
    let path = (simulator.device.runtime.root as NSString)
      .appendingPathComponent("bin")
      .appending("/launchctl")
    let binary = try FBBinaryDescriptor.binary(withPath: path)
    return binary.path
  }

  public class func commands(with simulator: FBSimulator) -> FBSimulatorLaunchCtlCommands {
    let launchctlLaunchPath = try! launchCtlLaunchPath(for: simulator)
    return FBSimulatorLaunchCtlCommands(simulator: simulator, launchctlLaunchPath: launchctlLaunchPath)
  }

  private init(simulator: FBSimulator, launchctlLaunchPath: String) {
    self.simulator = simulator
    self.launchctlLaunchPath = launchctlLaunchPath
    super.init()
  }

  // MARK: - Services

  fileprivate func serviceName(forProcessIdentifier pid: pid_t) async throws -> String {
    let pattern = "^\(NSRegularExpression.escapedPattern(for: "\(pid)"))\t"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      throw FBSimulatorError.describe("Couldn't build search pattern for '\(pid)'").build()
    }
    let (serviceName, _) = try await firstServiceNameAndProcessIdentifier(matching: regex)
    return serviceName
  }

  fileprivate func serviceNamesAndProcessIdentifiers(matching regex: NSRegularExpression) async throws -> [String: NSNumber] {
    let text = try await run(.list)
    let lines = text.components(separatedBy: .newlines)
    var mapping: [String: NSNumber] = [:]
    for line in lines {
      if regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) == nil {
        continue
      }
      var processIdentifier: pid_t = 0
      guard let serviceName = try? FBSimulatorLaunchCtlCommands.extractServiceName(fromListLine: line, processIdentifierOut: &processIdentifier) else {
        // If extraction fails, skip the line
        continue
      }
      mapping[serviceName] = NSNumber(value: processIdentifier)
    }
    return mapping
  }

  fileprivate func firstServiceNameAndProcessIdentifier(matching regex: NSRegularExpression) async throws -> (String, pid_t) {
    let serviceNameToProcessIdentifier = try await serviceNamesAndProcessIdentifiers(matching: regex)
    guard let (serviceName, processIdentifier) = serviceNameToProcessIdentifier.first else {
      throw FBSimulatorError.describe("No Matching processes for '\(regex.pattern)'").build()
    }
    if serviceNameToProcessIdentifier.count > 1 {
      throw FBSimulatorError.describe("Multiple Matching processes for '\(regex.pattern)' \(FBCollectionInformation.oneLineDescription(from: serviceNameToProcessIdentifier))").build()
    }
    return (serviceName, processIdentifier.int32Value)
  }

  fileprivate func listServices() async throws -> [String: Any] {
    let text = try await run(.list)
    let lines = text.components(separatedBy: .newlines)
    if lines.count < 2 {
      throw FBSimulatorError.describe("Insufficient number of lines from output '\(text)'").build()
    }
    var services: [String: Any] = [:]
    for (serviceName, processIdentifier) in Self.serviceMap(fromListOutput: text) {
      services[serviceName] = processIdentifier > 0 ? NSNumber(value: processIdentifier) : NSNull()
    }
    return services
  }

  fileprivate func stopService(withName serviceName: String) async throws -> String {
    do {
      return try await run(.stop(serviceName: serviceName))
    } catch {
      throw FBSimulatorError.describe("Failed to stop service '\(serviceName)'")
        .caused(by: error as NSError)
        .build()
    }
  }

  fileprivate func startService(withName serviceName: String) async throws -> String {
    do {
      return try await run(.start(serviceName: serviceName))
    } catch {
      throw FBSimulatorError.describe("Failed to start service '\(serviceName)'")
        .caused(by: error as NSError)
        .build()
    }
  }

  // MARK: - Helpers

  @objc
  public class func extractApplicationBundleIdentifier(fromServiceName serviceName: String) -> String? {
    guard let marker = serviceName.range(of: "UIKitApplication:") else {
      return nil
    }
    return String(serviceName[marker.upperBound...].prefix { $0 != "[" })
  }

  // MARK: - Private

  private class func extractServiceName(fromListLine line: String, processIdentifierOut: inout pid_t) throws -> String {
    let words = line.components(separatedBy: .whitespaces)
    guard words.count == 3, let processIdentifierString = words.first, let serviceName = words.last else {
      throw FBSimulatorError.describe("Output does not have exactly three words: \(FBCollectionInformation.oneLineDescription(from: words))").build()
    }
    if processIdentifierString == "-" {
      processIdentifierOut = -1
      return serviceName
    }

    let processIdentifierInteger = Int(processIdentifierString) ?? 0
    guard processIdentifierInteger >= 1 else {
      throw FBSimulatorError.describe("Expected a process identifier as first word, but got \(processIdentifierString) from \(FBCollectionInformation.oneLineDescription(from: words))").build()
    }
    processIdentifierOut = pid_t(processIdentifierInteger)
    return serviceName
  }

  // Parses `launchctl list` output into a service-name -> pid map: a pid of -1 marks a
  // loaded-but-not-running service (the "-" placeholder), >= 1 is a live process. The header
  // row and any malformed (non-three-column) lines are skipped. Static and internal so the
  // parsing can be unit-tested without spawning launchctl; see FBSimulatorLaunchCtlCommandsTests.
  static func serviceMap(fromListOutput text: String) -> [String: pid_t] {
    var services: [String: pid_t] = [:]
    for line in text.components(separatedBy: .newlines) {
      if line.isEmpty {
        continue
      }
      var processIdentifier: pid_t = -1
      guard let serviceName = try? extractServiceName(fromListLine: line, processIdentifierOut: &processIdentifier) else {
        continue
      }
      services[serviceName] = processIdentifier
    }
    return services
  }

  // The closed set of launchctl operations this command issues. Modelling them as an enum keeps argv
  // construction in one place and makes the operation set exhaustive, so a new operation cannot be
  // added without routing through `run`.
  enum Command {
    case list
    case stop(serviceName: String)
    case start(serviceName: String)

    var arguments: [String] {
      switch self {
      case .list:
        return ["list"]
      case let .stop(serviceName):
        return ["stop", serviceName]
      case let .start(serviceName):
        return ["start", serviceName]
      }
    }

    var exitCodePolicy: ExitCodePolicy {
      switch self {
      case .list:
        return .require([0])
      case .stop:
        // launchctl returns ESRCH (3) when the service is not running; for stop that is an idempotent
        // no-op. Any other non-zero is a genuine failure to stop a running service.
        return .require([0, 3])
      case .start:
        // For start, ESRCH (3) means there is no such service to start — a genuine failure, not a
        // no-op — so only a 0 exit is success.
        return .require([0])
      }
    }
  }

  private func run(_ command: Command) async throws -> String {
    let output = try await simulator.launchProcessConsumingOutput(launchPath: launchctlLaunchPath, arguments: command.arguments)
    return try FBSimulatorLaunchCtlCommands.stdout(orThrowFrom: output, command: command, logger: simulator.logger)
  }

  // Internal for unit-test coverage of the exit-code handling; see FBSimulatorLaunchCtlCommandsTests.
  static func stdout(orThrowFrom output: FBInSimulatorToolOutput, command: Command, logger: (any FBControlCoreLogger)?) throws -> String {
    if output.exitCode != 0 {
      let stderr = String(data: output.stderr, encoding: .utf8) ?? ""
      guard command.exitCodePolicy.accepts(output.exitCode) else {
        throw FBSimulatorError.describe("launchctl \(command.arguments.joined(separator: " ")) failed with exit code \(output.exitCode): \(stderr)").build()
      }
      logger?.log("launchctl \(command.arguments.joined(separator: " ")) exited with code \(output.exitCode): \(stderr)")
    }
    return String(data: output.stdout, encoding: .utf8) ?? ""
  }
}

// MARK: - FBSimulator+LaunchCtlCommands

extension FBSimulator: LaunchCtlCommands {

  public func serviceName(forProcessIdentifier pid: pid_t) async throws -> String {
    try await launchCtlCommands().serviceName(forProcessIdentifier: pid)
  }

  public func serviceName(forProcess process: FBProcessInfo) async throws -> String {
    try await launchCtlCommands().serviceName(forProcessIdentifier: process.processIdentifier)
  }

  public func serviceNamesAndProcessIdentifiers(matching regex: NSRegularExpression) async throws -> [String: NSNumber] {
    try await launchCtlCommands().serviceNamesAndProcessIdentifiers(matching: regex)
  }

  public func firstServiceNameAndProcessIdentifier(matching regex: NSRegularExpression) async throws -> (serviceName: String, processIdentifier: pid_t) {
    try await launchCtlCommands().firstServiceNameAndProcessIdentifier(matching: regex)
  }

  public func processIsRunning(onSimulator process: FBProcessInfo) async throws -> Bool {
    _ = try await launchCtlCommands().serviceName(forProcessIdentifier: process.processIdentifier)
    return true
  }

  public func listServices() async throws -> [String: Any] {
    try await launchCtlCommands().listServices()
  }

  public func stopService(withName serviceName: String) async throws -> String {
    try await launchCtlCommands().stopService(withName: serviceName)
  }

  public func startService(withName serviceName: String) async throws -> String {
    try await launchCtlCommands().startService(withName: serviceName)
  }
}
