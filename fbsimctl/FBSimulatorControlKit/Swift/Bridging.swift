/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
import Foundation

extension FBiOSTargetState {
  public var description: String {
    return FBiOSTargetStateStringFromState(self).rawValue
  }
}

extension FBiOSTargetQuery {
  static func parseUDIDToken(_ token: String) throws -> String {
    if let _ = UUID(uuidString: token) {
      return token
    }
    if token.count != 40 {
      throw ParseError.couldNotInterpret("UDID is not 40 characters long", token)
    }
    let nonDeviceUDIDSet = CharacterSet(charactersIn: "0123456789ABCDEFabcdef").inverted
    if let range = token.rangeOfCharacter(from: nonDeviceUDIDSet) {
      let invalidCharacters = token.substring(with: range)
      throw ParseError.couldNotInterpret("UDID contains non-hex character '\(invalidCharacters)'", token)
    }
    return token
  }
}

extension URL {
  static func urlRelativeTo(_ basePath: String, component: String, isDirectory: Bool) -> URL {
    let url = URL(fileURLWithPath: basePath)
    return url.appendingPathComponent(component, isDirectory: isDirectory)
  }

  var bridgedAbsoluteString: String {
    return absoluteString
  }
}

public typealias ControlCoreValue = FBJSONSerializable & CustomStringConvertible

@objc open class ControlCoreLoggerBridge: NSObject {
  let reporter: EventReporter

  init(reporter: EventReporter) {
    self.reporter = reporter
  }

  @objc open func log(_ level: Int32, string: String) {
    let subject = FBEventReporterSubject(logString: string, level: level)
    reporter.report(subject)
  }
}

extension FBiOSTargetType: Accumulator {
  public func append(_ other: FBiOSTargetType) -> FBiOSTargetType {
    return self == FBiOSTargetType.all ? intersection(other) : union(other)
  }
}

extension FBiOSTargetQuery {
  public static func ofCount(_ count: Int) -> FBiOSTargetQuery {
    return allTargets().ofCount(count)
  }

  public func ofCount(_ count: Int) -> FBiOSTargetQuery {
    return range(NSRange(location: 0, length: count))
  }
}

extension FBiOSTargetQuery: Accumulator {
  public func append(_ other: FBiOSTargetQuery) -> Self {
    let targetType = self.targetType.append(other.targetType)

    return udids(Array(other.udids))
      .names(Array(other.names))
      .states(other.states)
      .architectures(Array(other.architectures))
      .targetType(targetType)
      .osVersions(Array(other.osVersions))
      .devices(Array(other.devices))
      .range(other.range)
  }
}

extension FBiOSTargetFormatKey {
  public static var allFields: [FBiOSTargetFormatKey] {
    return [
      FBiOSTargetFormatKey.UDID,
      FBiOSTargetFormatKey.name,
      FBiOSTargetFormatKey.model,
      FBiOSTargetFormatKey.osVersion,
      FBiOSTargetFormatKey.state,
      FBiOSTargetFormatKey.architecture,
      FBiOSTargetFormatKey.processIdentifier,
      FBiOSTargetFormatKey.containerApplicationProcessIdentifier,
    ]
  }
}

extension FBArchitecture {
  public static var allFields: [FBArchitecture] {
    return [
      .I386,
      .X86_64,
      .armv7,
      .armv7s,
      .arm64,
    ]
  }
}

extension FBiOSTargetFormat: Accumulator {
  public func append(_ other: FBiOSTargetFormat) -> Self {
    return appendFields(other.fields)
  }
}

extension FBSimulatorBootConfiguration: Accumulator {
  public func append(_ other: FBSimulatorBootConfiguration) -> Self {
    var configuration = self
    if let locale = other.localizationOverride ?? self.localizationOverride {
      configuration = configuration.withLocalizationOverride(locale)
    }
    if let framebuffer = other.framebuffer ?? self.framebuffer {
      configuration = configuration.withFramebuffer(framebuffer)
    }
    if let scale = other.scale ?? self.scale {
      configuration = configuration.withScale(scale)
    }
    configuration = configuration.withOptions(options.union(other.options))
    return configuration
  }
}

extension FBProcessOutputConfiguration: Accumulator {
  public func append(_ other: FBProcessOutputConfiguration) -> Self {
    var configuration = self
    if other.stdOut is String {
      configuration = try! configuration.withStdOut(other.stdOut)
    }
    if other.stdErr is String {
      configuration = try! configuration.withStdErr(other.stdErr)
    }
    return configuration
  }
}

extension IndividualCreationConfiguration {
  public var simulatorConfiguration: FBSimulatorConfiguration {
    var configuration = FBSimulatorConfiguration.default()
    if let model = self.model {
      configuration = configuration.withDeviceModel(model)
    }
    if let os = self.os {
      configuration = configuration.withOSNamed(os)
    }
    if let auxDirectory = self.auxDirectory {
      configuration = configuration.withAuxillaryDirectory(auxDirectory)
    }
    return configuration
  }
}

extension Bool {
  static func fallback(from: String?, to _: Bool) -> Bool {
    guard let from = from else {
      return false
    }
    switch from.lowercased() {
    case "1", "true": return true
    case "0", "false": return false
    default: return false
    }
  }
}

extension HttpRequest {
  func getBoolQueryParam(_ key: String, _ fallback: Bool) -> Bool {
    return Bool.fallback(from: query[key], to: fallback)
  }
}

extension FBiOSTargetFutureType {
  public var eventName: EventName {
    switch self {
    case FBiOSTargetFutureType.applicationLaunch:
      return .launch
    case FBiOSTargetFutureType.agentLaunch:
      return .launch
    case FBiOSTargetFutureType.testLaunch:
      return .launchXCTest
    default:
      return EventName(rawValue: rawValue)
    }
  }
}

extension FBiOSTargetFuture {
  public var eventName: EventName {
    return type(of: self).futureType.eventName
  }

  public var printable: String {
    let json = try! JSON.encode(FBiOSActionRouter.json(fromAction: self) as AnyObject)
    return try! json.serializeToString(false)
  }
}

extension FBProcessLaunchConfiguration: EnvironmentAdditive {}

extension FBTestLaunchConfiguration: EnvironmentAdditive {
  func withEnvironmentAdditions(_ environmentAdditions: [String: String]) -> Self {
    guard let appLaunchConf = self.applicationLaunchConfiguration else {
      return self
    }
    return withApplicationLaunchConfiguration(appLaunchConf.withEnvironmentAdditions(environmentAdditions))
  }
}

public typealias Writer = FBDataConsumer
public extension Writer {
  func write(_ string: String) {
    var output = string
    if output.last != "\n" {
      output.append("\n" as Character)
    }
    guard let data = output.data(using: String.Encoding.utf8) else {
      return
    }
    consumeData(data)
  }
}

public typealias FileHandleWriter = FBDataConsumer
public extension FBFileWriter {
  static var stdOutWriter: FileHandleWriter {
    return FBFileWriter.syncWriter(withFileDescriptor: FileHandle.standardOutput.fileDescriptor, closeOnEndOfFile: false)
  }

  static var stdErrWriter: FileHandleWriter {
    return FBFileWriter.syncWriter(withFileDescriptor: FileHandle.standardError.fileDescriptor, closeOnEndOfFile: false)
  }
}

public typealias EventType = FBEventType

public typealias JSONKeys = FBJSONKey
