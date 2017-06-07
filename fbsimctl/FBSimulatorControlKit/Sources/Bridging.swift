/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation
import FBSimulatorControl

extension FBSimulatorState {
  public var description: String { get {
    return FBSimulator.stateString(from: self)
  }}
}

extension FBiOSTargetQuery {
  static func parseUDIDToken(_ token: String) throws -> String {
    if let _ = UUID(uuidString: token) {
      return token
    }
    if token.characters.count != 40 {
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

  var bridgedAbsoluteString: String { get {
    return self.absoluteString
  }}
}

public typealias ControlCoreValue = FBJSONSerializable & CustomStringConvertible

@objc open class ControlCoreLoggerBridge : NSObject {
  let reporter: EventReporter

  init(reporter: EventReporter) {
    self.reporter = reporter
  }

  @objc open func log(_ level: Int32, string: String) {
    let subject = LogSubject(logString: string, level: level)
    self.reporter.report(subject)
  }
}

extension FBiOSTargetType : Accumulator {
  public func append(_ other: FBiOSTargetType) -> FBiOSTargetType {
    return self == FBiOSTargetType.all ? self.intersection(other) : self.union(other)
  }
}

extension FBiOSTargetQuery {
  public static func ofCount(_ count: Int) -> FBiOSTargetQuery {
    return self.allTargets().ofCount(count)
  }

  public func ofCount(_ count: Int) -> FBiOSTargetQuery {
    return self.range(NSRange(location: 0, length: count))
  }
}

extension FBiOSTargetQuery : Accumulator {
  public func append(_ other: FBiOSTargetQuery) -> Self {
    let targetType = self.targetType.append(other.targetType)

    return self
      .udids(Array(other.udids))
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
  public static var allFields: [FBiOSTargetFormatKey] { get {
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
  }}
}

extension FBArchitecture {
  public static var allFields: [FBArchitecture] { get {
    return [
      .I386,
      .X86_64,
      .armv7,
      .armv7s,
      .arm64,
    ]
  }}
}

extension FBiOSTargetFormat : Accumulator {
  public func append(_ other: FBiOSTargetFormat) -> Self {
    return self.appendFields(other.fields)
  }
}

extension FBSimulatorBootConfiguration : Accumulator {
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
    configuration = configuration.withOptions(self.options.union(other.options))
    return configuration;
  }
}

extension FBProcessOutputConfiguration : Accumulator {
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
  public var simulatorConfiguration : FBSimulatorConfiguration { get {
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
  }}
}

extension FBApplicationDescriptor {
  static func findOrExtract(atPath: String) throws -> (String, URL?) {
    var url: NSURL? = nil
    let result = try FBApplicationDescriptor.findOrExtractApplication(atPath: atPath, extractPathOut: &url)
    return (result, url as URL?)
  }
}

extension Bool {
  static func fallback(from: String?, to: Bool) -> Bool {
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
    return Bool.fallback(from: self.query[key], to: fallback)
  }
}

struct LineBufferDataIterator : IteratorProtocol {
  let lineBuffer: FBLineBuffer

  mutating func next() -> Data? {
    return self.lineBuffer.consumeLineData()
  }
}

struct LineBufferStringIterator : IteratorProtocol {
  let lineBuffer: FBLineBuffer

  mutating func next() -> String? {
    return self.lineBuffer.consumeLineString()
  }
}

extension FBLineBuffer {
  func dataIterator() -> LineBufferDataIterator {
    return LineBufferDataIterator(lineBuffer: self)
  }

  func stringIterator() -> LineBufferStringIterator {
    return LineBufferStringIterator(lineBuffer: self)
  }
}

@objc class AccumilatingActionDelegate : NSObject, FBiOSTargetActionDelegate {
  var handle: FBTerminationHandle? = nil
  let reporter: EventReporter

  init(reporter: EventReporter) {
    self.reporter = reporter
    super.init()
  }

  func action(_ action: FBiOSTargetAction, target: FBiOSTarget, didGenerate terminationHandle: FBTerminationHandle) {
    self.handle = terminationHandle
  }
}

@objc class ActionReaderDelegateBridge : NSObject, FBiOSActionReaderDelegate {
  let interpreter: EventInterpreter
  let reporter: EventReporter

  init(interpreter: EventInterpreter, reporter: EventReporter) {
    self.interpreter = interpreter
    self.reporter = reporter
    super.init()
  }

  func interpret(_ action: FBiOSTargetAction, _ eventType: EventType) -> String {
    let subject = SimpleSubject(action.eventName, eventType, ControlCoreSubject(action as! ControlCoreValue))
    return self.interpret(subject)
  }

  func interpret(_ subject: EventReporterSubject) -> String {
    self.reporter.report(subject)
    let lines = self.interpreter.interpret(subject)
    return lines.joined(separator: "\n") + "\n"
  }

  func readerDidFinishReading(_ reader: FBiOSActionReader) {

  }

  func reader(_ reader: FBiOSActionReader, failedToInterpretInput input: String, error: Error) -> String? {
    let message = error.localizedDescription + ". input: " + input
    let subject = SimpleSubject(.failure, .discrete, message)
    return self.interpret(subject)
  }

  func reader(_ reader: FBiOSActionReader, willStartReadingUpload header: FBUploadHeader) -> String? {
    return self.interpret(header, .started)
  }

  func reader(_ reader: FBiOSActionReader, didFinishUpload destination: FBUploadedDestination) -> String? {
    return self.interpret(destination, .ended)
  }

  func reader(_ reader: FBiOSActionReader, willStartPerforming action: FBiOSTargetAction, on target: FBiOSTarget) -> String? {
    return self.interpret(action, .started)
  }

  func reader(_ reader: FBiOSActionReader, didProcessAction action: FBiOSTargetAction, on target: FBiOSTarget) -> String? {
    return self.interpret(action, .ended)
  }

  func reader(_ reader: FBiOSActionReader, didFailToProcessAction action: FBiOSTargetAction, on target: FBiOSTarget, error: Error) -> String? {
    let subject = SimpleSubject(.failure, .discrete, error.localizedDescription)
    return self.interpret(subject)
  }

}

extension FBiOSTargetAction {
  func runAction(target: FBiOSTarget, reporter: EventReporter) throws -> FBTerminationHandle? {
    let delegate = AccumilatingActionDelegate(reporter: reporter)
    try self.run(with: target, delegate: delegate)
    return delegate.handle
  }

  public var eventName: EventName { get {
    let actionType = type(of: self).actionType
    switch actionType {
    case FBiOSTargetActionType.applicationLaunch:
      return .launch
    case FBiOSTargetActionType.agentLaunch:
      return .launch
    case FBiOSTargetActionType.testLaunch:
      return .launchXCTest
    default:
      return actionType
    }
  }}

  public func printable() -> String {
    let json = try! JSON.encode(FBiOSActionRouter.json(from: self) as AnyObject)
    return try! json.serializeToString(false)
  }
}

extension FBProcessLaunchConfiguration : EnvironmentAdditive {}

extension FBTestLaunchConfiguration : EnvironmentAdditive {
  func withEnvironmentAdditions(_ environmentAdditions: [String : String]) -> Self {
    guard let appLaunchConf = self.applicationLaunchConfiguration else {
      return self
    }
    return self.withApplicationLaunchConfiguration(appLaunchConf.withEnvironmentAdditions(environmentAdditions))
  }
}
