// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

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

  // MARK: - Querying Services

  @objc
  public func serviceName(forProcessIdentifier pid: pid_t) -> FBFuture<NSString> {
    let pattern = "^\(NSRegularExpression.escapedPattern(for: "\(pid)"))\t"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      return FBSimulatorError.describe("Couldn't build search pattern for '\(pid)'")
        .failFuture() as! FBFuture<NSString>
    }

    return
      (unsafeBitCast(self.firstServiceNameAndProcessIdentifier(matching: regex), to: FBFuture<AnyObject>.self)
      .onQueue(
        simulator.asyncQueue,
        map: { (tuple: Any) -> NSString in
          let arr = tuple as! [Any]
          return arr[0] as! NSString
        })) as! FBFuture<NSString>
  }

  @objc
  public func serviceName(forProcess process: FBProcessInfo) -> FBFuture<NSString> {
    return serviceName(forProcessIdentifier: process.processIdentifier)
  }

  @objc
  public func serviceNamesAndProcessIdentifiers(matching regex: NSRegularExpression) -> FBFuture<NSDictionary> {
    return (runWithArguments(["list"]) as FBFuture)
      .onQueue(
        simulator.asyncQueue,
        fmap: { (text: Any) -> FBFuture<AnyObject> in
          let text = text as! String
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
          return FBFuture(result: mapping as NSDictionary)
        }) as! FBFuture<NSDictionary>
  }

  @objc
  public func firstServiceNameAndProcessIdentifier(matching regex: NSRegularExpression) -> FBFuture<NSArray> {
    return
      (unsafeBitCast(serviceNamesAndProcessIdentifiers(matching: regex), to: FBFuture<AnyObject>.self)
      .onQueue(
        simulator.asyncQueue,
        fmap: { (result: Any) -> FBFuture<AnyObject> in
          let serviceNameToProcessIdentifier = result as! [String: NSNumber]
          if serviceNameToProcessIdentifier.isEmpty {
            return FBSimulatorError.describe("No Matching processes for '\(regex.pattern)'")
              .failFuture()
          }
          if serviceNameToProcessIdentifier.count > 1 {
            return FBSimulatorError.describe("Multiple Matching processes for '\(regex.pattern)' \(FBCollectionInformation.oneLineDescription(from: serviceNameToProcessIdentifier))")
              .failFuture()
          }
          let serviceName = serviceNameToProcessIdentifier.keys.first!
          let processIdentifier = serviceNameToProcessIdentifier.values.first!
          return FBFuture(result: [serviceName, processIdentifier] as NSArray)
        })) as! FBFuture<NSArray>
  }

  @objc
  public func processIsRunning(onSimulator process: FBProcessInfo) -> FBFuture<NSNumber> {
    return
      (unsafeBitCast(serviceName(forProcess: process), to: FBFuture<AnyObject>.self)
      .onQueue(
        simulator.workQueue,
        map: { (_: Any) -> NSNumber in
          return NSNumber(value: true)
        })) as! FBFuture<NSNumber>
  }

  @objc
  public func listServices() -> FBFuture<NSDictionary> {
    return (runWithArguments(["list"]) as FBFuture)
      .onQueue(
        simulator.asyncQueue,
        fmap: { (text: Any) -> FBFuture<AnyObject> in
          let text = text as! String
          let lines = text.components(separatedBy: .newlines)
          if lines.count < 2 {
            return FBSimulatorError.describe("Insufficient number of lines from output '\(text)'")
              .failFuture()
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
          return FBFuture(result: services as NSDictionary)
        }) as! FBFuture<NSDictionary>
  }

  // MARK: - Manipulating Services

  @objc
  public func stopService(withName serviceName: String) -> FBFuture<NSString> {
    return (runWithArguments(["stop", serviceName]) as FBFuture)
      .rephraseFailure("Failed to stop service '\(serviceName)'") as! FBFuture<NSString>
  }

  @objc
  public func startService(withName serviceName: String) -> FBFuture<NSString> {
    return (runWithArguments(["start", serviceName]) as FBFuture)
      .rephraseFailure("Failed to start service '\(serviceName)'") as! FBFuture<NSString>
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

  private func runWithArguments(_ arguments: [String]) -> FBFuture<NSString> {
    let launchConfiguration = FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>(
      launchPath: launchctlLaunchPath,
      arguments: arguments,
      environment: [:],
      io: FBProcessIO.outputToDevNull(),
      mode: .default
    )
    return FBProcessSpawnCommandHelpers.launchConsumingStdout(launchConfiguration, withCommands: simulator)
  }
}
