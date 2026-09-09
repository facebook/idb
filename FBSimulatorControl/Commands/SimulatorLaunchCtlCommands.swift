/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

public enum FBSimulatorLaunchCtlError: Error {
  case searchPatternConstructionFailed(processIdentifier: pid_t)
  case noMatchingProcesses(pattern: String)
  case multipleMatchingProcesses(pattern: String, matches: [String: NSNumber])
  case insufficientOutput(output: String)
  case stopFailed(serviceName: String, underlying: Error)
  case startFailed(serviceName: String, underlying: Error)
  case malformedListLine(words: [String])
  case invalidProcessIdentifier(word: String, words: [String])
  case commandFailed(arguments: [String], exitCode: Int32, stderr: String)
}

extension FBSimulatorLaunchCtlError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .searchPatternConstructionFailed(processIdentifier):
      return "Couldn't build search pattern for '\(processIdentifier)'"
    case let .noMatchingProcesses(pattern):
      return "No Matching processes for '\(pattern)'"
    case let .multipleMatchingProcesses(pattern, matches):
      return "Multiple Matching processes for '\(pattern)' \(FBCollectionInformation.oneLineDescription(from: matches))"
    case let .insufficientOutput(output):
      return "Insufficient number of lines from output '\(output)'"
    case let .stopFailed(serviceName, _):
      return "Failed to stop service '\(serviceName)'"
    case let .startFailed(serviceName, _):
      return "Failed to start service '\(serviceName)'"
    case let .malformedListLine(words):
      return "Output does not have exactly three words: \(FBCollectionInformation.oneLineDescription(from: words))"
    case let .invalidProcessIdentifier(word, words):
      return "Expected a process identifier as first word, but got \(word) from \(FBCollectionInformation.oneLineDescription(from: words))"
    case let .commandFailed(arguments, exitCode, stderr):
      return "launchctl \(arguments.joined(separator: " ")) failed with exit code \(exitCode): \(stderr)"
    }
  }
}

public final class FBSimulatorLaunchCtlCommands {

  private let simulator: FBSimulator

  // MARK: - Initializers

  private class func launchCtlLaunchPath(for simulator: FBSimulator) throws -> String {
    let path = (simulator.device.runtime.root as NSString)
      .appendingPathComponent("bin")
      .appending("/launchctl")
    let binary = try FBBinaryDescriptor.binary(withPath: path)
    return binary.path
  }

  public class func commands(with simulator: FBSimulator) -> FBSimulatorLaunchCtlCommands {
    FBSimulatorLaunchCtlCommands(simulator: simulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  // MARK: - Services

  fileprivate func serviceName(forProcessIdentifier pid: pid_t) async throws -> String {
    let pattern = "^\(NSRegularExpression.escapedPattern(for: "\(pid)"))\t"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      throw FBSimulatorLaunchCtlError.searchPatternConstructionFailed(processIdentifier: pid)
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
        continue
      }
      mapping[serviceName] = NSNumber(value: processIdentifier)
    }
    return mapping
  }

  fileprivate func firstServiceNameAndProcessIdentifier(matching regex: NSRegularExpression) async throws -> (String, pid_t) {
    let serviceNameToProcessIdentifier = try await serviceNamesAndProcessIdentifiers(matching: regex)
    guard let (serviceName, processIdentifier) = serviceNameToProcessIdentifier.first else {
      throw FBSimulatorLaunchCtlError.noMatchingProcesses(pattern: regex.pattern)
    }
    if serviceNameToProcessIdentifier.count > 1 {
      throw FBSimulatorLaunchCtlError.multipleMatchingProcesses(pattern: regex.pattern, matches: serviceNameToProcessIdentifier)
    }
    return (serviceName, processIdentifier.int32Value)
  }

  fileprivate func listServices() async throws -> [String: Any] {
    let text = try await run(.list)
    let lines = text.components(separatedBy: .newlines)
    if lines.count < 2 {
      throw FBSimulatorLaunchCtlError.insufficientOutput(output: text)
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
      throw FBSimulatorLaunchCtlError.stopFailed(serviceName: serviceName, underlying: error)
    }
  }

  fileprivate func startService(withName serviceName: String) async throws -> String {
    do {
      return try await run(.start(serviceName: serviceName))
    } catch {
      throw FBSimulatorLaunchCtlError.startFailed(serviceName: serviceName, underlying: error)
    }
  }

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
      throw FBSimulatorLaunchCtlError.malformedListLine(words: words)
    }
    if processIdentifierString == "-" {
      processIdentifierOut = -1
      return serviceName
    }

    let processIdentifierInteger = Int(processIdentifierString) ?? 0
    guard processIdentifierInteger >= 1 else {
      throw FBSimulatorLaunchCtlError.invalidProcessIdentifier(word: processIdentifierString, words: words)
    }
    processIdentifierOut = pid_t(processIdentifierInteger)
    return serviceName
  }

  // A pid of -1 marks a loaded-but-not-running service (the "-" placeholder). The header row and
  // malformed lines are skipped.
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
    let output = try await simulator.launchProcessConsumingOutput(launchPath: Self.launchCtlLaunchPath(for: simulator), arguments: command.arguments)
    return try FBSimulatorLaunchCtlCommands.stdout(orThrowFrom: output, command: command, logger: simulator.logger)
  }

  static func stdout(orThrowFrom output: FBInSimulatorToolOutput, command: Command, logger: (any FBControlCoreLogger)?) throws -> String {
    if output.exitCode != 0 {
      let stderr = String(data: output.stderr, encoding: .utf8) ?? ""
      guard command.exitCodePolicy.accepts(output.exitCode) else {
        throw FBSimulatorLaunchCtlError.commandFailed(arguments: command.arguments, exitCode: output.exitCode, stderr: stderr)
      }
      logger?.log("launchctl \(command.arguments.joined(separator: " ")) exited with code \(output.exitCode): \(stderr)")
    }
    return String(data: output.stdout, encoding: .utf8) ?? ""
  }
}

// MARK: - FBSimulator+LaunchCtlCommands

extension FBSimulator: LaunchCtlCommands {

  public func serviceName(forProcessIdentifier pid: pid_t) async throws -> String {
    try await launchCtl.serviceName(forProcessIdentifier: pid)
  }

  public func serviceName(forProcess process: FBProcessInfo) async throws -> String {
    try await launchCtl.serviceName(forProcessIdentifier: process.processIdentifier)
  }

  public func serviceNamesAndProcessIdentifiers(matching regex: NSRegularExpression) async throws -> [String: NSNumber] {
    try await launchCtl.serviceNamesAndProcessIdentifiers(matching: regex)
  }

  public func firstServiceNameAndProcessIdentifier(matching regex: NSRegularExpression) async throws -> (serviceName: String, processIdentifier: pid_t) {
    try await launchCtl.firstServiceNameAndProcessIdentifier(matching: regex)
  }

  public func processIsRunning(onSimulator process: FBProcessInfo) async throws -> Bool {
    _ = try await launchCtl.serviceName(forProcessIdentifier: process.processIdentifier)
    return true
  }

  public func listServices() async throws -> [String: Any] {
    try await launchCtl.listServices()
  }

  public func stopService(withName serviceName: String) async throws -> String {
    try await launchCtl.stopService(withName: serviceName)
  }

  public func startService(withName serviceName: String) async throws -> String {
    try await launchCtl.startService(withName: serviceName)
  }
}
