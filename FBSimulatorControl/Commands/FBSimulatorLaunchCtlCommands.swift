/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

// swiftlint:disable force_unwrapping

@objc public protocol FBSimulatorLaunchCtlCommandsProtocol: NSObjectProtocol, FBiOSTargetCommand {
  @objc(serviceNameForProcessIdentifier:)
  func serviceName(forProcessIdentifier pid: pid_t) -> FBFuture<NSString>

  @objc(serviceNameForProcess:)
  func serviceName(forProcess process: FBProcessInfo) -> FBFuture<NSString>

  @objc(serviceNamesAndProcessIdentifiersMatching:)
  func serviceNamesAndProcessIdentifiers(matching regex: NSRegularExpression) -> FBFuture<NSDictionary>

  @objc(firstServiceNameAndProcessIdentifierMatching:)
  func firstServiceNameAndProcessIdentifier(matching regex: NSRegularExpression) -> FBFuture<NSArray>

  @objc(processIsRunningOnSimulator:)
  func processIsRunning(onSimulator process: FBProcessInfo) -> FBFuture<NSNumber>

  func listServices() -> FBFuture<NSDictionary>

  @objc(stopServiceWithName:)
  func stopService(withName serviceName: String) -> FBFuture<NSString>

  @objc(startServiceWithName:)
  func startService(withName serviceName: String) -> FBFuture<NSString>
}

@objc(FBSimulatorLaunchCtlCommands)
public final class FBSimulatorLaunchCtlCommands: NSObject, FBSimulatorLaunchCtlCommandsProtocol {

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

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorLaunchCtlCommands {
    let simulator = target as! FBSimulator
    let launchctlLaunchPath = try! launchCtlLaunchPath(for: simulator)
    return FBSimulatorLaunchCtlCommands(simulator: simulator, launchctlLaunchPath: launchctlLaunchPath)
  }

  private init(simulator: FBSimulator, launchctlLaunchPath: String) {
    self.simulator = simulator
    self.launchctlLaunchPath = launchctlLaunchPath
    super.init()
  }

  // MARK: - Querying Services (legacy FBFuture entry points)

  @objc
  public func serviceName(forProcessIdentifier pid: pid_t) -> FBFuture<NSString> {
    fbFutureFromAsync { [self] in
      try await serviceNameAsync(forProcessIdentifier: pid) as NSString
    }
  }

  @objc
  public func serviceName(forProcess process: FBProcessInfo) -> FBFuture<NSString> {
    fbFutureFromAsync { [self] in
      try await serviceNameAsync(forProcessIdentifier: process.processIdentifier) as NSString
    }
  }

  @objc
  public func serviceNamesAndProcessIdentifiers(matching regex: NSRegularExpression) -> FBFuture<NSDictionary> {
    fbFutureFromAsync { [self] in
      try await serviceNamesAndProcessIdentifiersAsync(matching: regex) as NSDictionary
    }
  }

  @objc
  public func firstServiceNameAndProcessIdentifier(matching regex: NSRegularExpression) -> FBFuture<NSArray> {
    fbFutureFromAsync { [self] in
      let (serviceName, processIdentifier) = try await firstServiceNameAndProcessIdentifierAsync(matching: regex)
      return [serviceName, NSNumber(value: processIdentifier)] as NSArray
    }
  }

  @objc
  public func processIsRunning(onSimulator process: FBProcessInfo) -> FBFuture<NSNumber> {
    fbFutureFromAsync { [self] in
      _ = try await serviceNameAsync(forProcessIdentifier: process.processIdentifier)
      return NSNumber(value: true)
    }
  }

  @objc
  public func listServices() -> FBFuture<NSDictionary> {
    fbFutureFromAsync { [self] in
      try await listServicesAsync() as NSDictionary
    }
  }

  // MARK: - Manipulating Services (legacy FBFuture entry points)

  @objc
  public func stopService(withName serviceName: String) -> FBFuture<NSString> {
    fbFutureFromAsync { [self] in
      try await stopServiceAsync(withName: serviceName) as NSString
    }
  }

  @objc
  public func startService(withName serviceName: String) -> FBFuture<NSString> {
    fbFutureFromAsync { [self] in
      try await startServiceAsync(withName: serviceName) as NSString
    }
  }

  // MARK: - Async

  fileprivate func serviceNameAsync(forProcessIdentifier pid: pid_t) async throws -> String {
    let pattern = "^\(NSRegularExpression.escapedPattern(for: "\(pid)"))\t"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      throw FBSimulatorError.describe("Couldn't build search pattern for '\(pid)'").build()
    }
    let (serviceName, _) = try await firstServiceNameAndProcessIdentifierAsync(matching: regex)
    return serviceName
  }

  fileprivate func serviceNamesAndProcessIdentifiersAsync(matching regex: NSRegularExpression) async throws -> [String: NSNumber] {
    let text = try await runWithArgumentsAsync(["list"])
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

  fileprivate func firstServiceNameAndProcessIdentifierAsync(matching regex: NSRegularExpression) async throws -> (String, pid_t) {
    let serviceNameToProcessIdentifier = try await serviceNamesAndProcessIdentifiersAsync(matching: regex)
    if serviceNameToProcessIdentifier.isEmpty {
      throw FBSimulatorError.describe("No Matching processes for '\(regex.pattern)'").build()
    }
    if serviceNameToProcessIdentifier.count > 1 {
      throw FBSimulatorError.describe("Multiple Matching processes for '\(regex.pattern)' \(FBCollectionInformation.oneLineDescription(from: serviceNameToProcessIdentifier))").build()
    }
    let serviceName = serviceNameToProcessIdentifier.keys.first!
    let processIdentifier = serviceNameToProcessIdentifier.values.first!.int32Value
    return (serviceName, processIdentifier)
  }

  fileprivate func listServicesAsync() async throws -> [String: Any] {
    let text = try await runWithArgumentsAsync(["list"])
    let lines = text.components(separatedBy: .newlines)
    if lines.count < 2 {
      throw FBSimulatorError.describe("Insufficient number of lines from output '\(text)'").build()
    }
    let serviceLines = Array(lines.dropFirst())

    var services: [String: Any] = [:]
    for line in serviceLines {
      if line.isEmpty {
        continue
      }
      var processIdentifier: pid_t = -1
      guard let serviceName = try? FBSimulatorLaunchCtlCommands.extractServiceName(fromListLine: line, processIdentifierOut: &processIdentifier) else {
        continue
      }
      services[serviceName] = processIdentifier > 0 ? NSNumber(value: processIdentifier) : NSNull()
    }
    return services
  }

  fileprivate func stopServiceAsync(withName serviceName: String) async throws -> String {
    do {
      return try await runWithArgumentsAsync(["stop", serviceName])
    } catch {
      throw FBSimulatorError.describe("Failed to stop service '\(serviceName)'")
        .caused(by: error as NSError)
        .build()
    }
  }

  fileprivate func startServiceAsync(withName serviceName: String) async throws -> String {
    do {
      return try await runWithArgumentsAsync(["start", serviceName])
    } catch {
      throw FBSimulatorError.describe("Failed to start service '\(serviceName)'")
        .caused(by: error as NSError)
        .build()
    }
  }

  // MARK: - Helpers

  @objc
  public class func extractApplicationBundleIdentifier(fromServiceName serviceName: String) -> String? {
    let regex = regularExpressionForServiceNameToBundleID
    guard let result = regex.firstMatch(in: serviceName, options: [], range: NSRange(location: 0, length: serviceName.count)) else {
      return nil
    }
    let range = result.range(at: 1)
    return (serviceName as NSString).substring(with: range)
  }

  // MARK: - Private

  private static let regularExpressionForServiceNameToBundleID: NSRegularExpression = {
    return try! NSRegularExpression(pattern: "UIKitApplication:([^\\[]*).*", options: .dotMatchesLineSeparators)
  }()

  private class func extractServiceName(fromListLine line: String, processIdentifierOut: inout pid_t) throws -> String {
    let words = line.components(separatedBy: .whitespaces)
    guard words.count == 3 else {
      throw FBSimulatorError.describe("Output does not have exactly three words: \(FBCollectionInformation.oneLineDescription(from: words))").build()
    }
    let serviceName = words.last!
    let processIdentifierString = words.first!
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

  private func runWithArgumentsAsync(_ arguments: [String]) async throws -> String {
    let launchConfiguration = FBProcessSpawnConfiguration(
      launchPath: launchctlLaunchPath,
      arguments: arguments,
      environment: [:],
      io: FBProcessIO.outputToDevNull(),
      mode: .default
    )
    let result = try await bridgeFBFuture(FBProcessSpawnCommandHelpers.launchConsumingStdout(launchConfiguration, withCommands: simulator))
    return result as String
  }
}
