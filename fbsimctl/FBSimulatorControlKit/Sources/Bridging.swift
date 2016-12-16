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

class Interaction : NSObject, FBInteractionProtocol {
  let interaction:(Void)throws -> Void

  init(_ interaction: @escaping (Void) throws -> Void) {
    self.interaction = interaction
  }

  func perform() throws {
    return try self.interaction()
  }
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
  public static func simulatorStates(_ states: [FBSimulatorState]) -> FBiOSTargetQuery {
    return self.allTargets().simulatorStates(states)
  }

  public func simulatorStates(_ states: [FBSimulatorState]) -> FBiOSTargetQuery {
    let indexSet = states.reduce(NSMutableIndexSet()) { (indexSet, state) in
      indexSet.add(Int(state.rawValue))
      return indexSet
    }
    return self.states(indexSet as IndexSet)
  }

  public static func ofCount(_ count: Int) -> FBiOSTargetQuery {
    return self.allTargets().ofCount(count)
  }

  public func ofCount(_ count: Int) -> FBiOSTargetQuery {
    return self.range(NSRange(location: 0, length: count))
  }
}

extension FBiOSTargetQuery : Accumulator {
  public func append(_ other: FBiOSTargetQuery) -> Self {
    let deviceSet = other.devices as NSSet
    let deviceArray = Array(deviceSet) as! [FBControlCoreConfiguration_Device]
    let osVersionsSet = other.osVersions as NSSet
    let osVersionsArray = Array(osVersionsSet) as! [FBControlCoreConfiguration_OS]
    let targetType = self.targetType.append(other.targetType)

    return self
      .udids(Array(other.udids))
      .states(other.states)
      .targetType(targetType)
      .devices(deviceArray)
      .osVersions(osVersionsArray)
      .range(other.range)
  }
}

extension FBiOSTargetFormat {
  public static var allFields: [String] { get {
    return [
      FBiOSTargetFormatUDID,
      FBiOSTargetFormatName,
      FBiOSTargetFormatDeviceName,
      FBiOSTargetFormatOSVersion,
      FBiOSTargetFormatState,
      FBiOSTargetFormatProcessIdentifier,
      FBiOSTargetFormatContainerApplicationProcessIdentifier,
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
    if let device = self.deviceType {
      configuration = configuration.withDevice(device)
    }
    if let os = self.osVersion {
      configuration = configuration.withOS(os)
    }
    if let auxDirectory = self.auxDirectory {
      configuration = configuration.withAuxillaryDirectory(auxDirectory)
    }
    return configuration
  }}
}
