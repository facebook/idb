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
    return FBSimulator.stateStringFromSimulatorState(self)
  }}
}

extension NSURL {
  static func urlRelativeTo(basePath: String, component: String, isDirectory: Bool) -> NSURL {
    let url = NSURL(fileURLWithPath: basePath)
    #if swift(>=2.3)
      return url.URLByAppendingPathComponent(component, isDirectory: isDirectory)!
    #else
      return url.URLByAppendingPathComponent(component, isDirectory: isDirectory)
    #endif
  }

  var bridgedAbsoluteString: String { get {
    #if swift(>=2.3)
      return self.absoluteString!
    #else
      return self.absoluteString
    #endif
  }}

}

public typealias ControlCoreValue = protocol<FBJSONSerializable, CustomStringConvertible>

@objc public class ControlCoreLoggerBridge : NSObject {
  let reporter: EventReporter

  init(reporter: EventReporter) {
    self.reporter = reporter
  }

  @objc public func log(level: Int32, string: String) {
    let subject = LogSubject(logString: string, level: level)
    self.reporter.report(subject)
  }
}

extension FBiOSTargetType : Accumulator {
  public func append(other: FBiOSTargetType) -> FBiOSTargetType {
    return self == FBiOSTargetType.All ? self.intersect(other) : self.union(other)
  }
}

extension FBiOSTargetQuery {
  public static func simulatorStates(states: [FBSimulatorState]) -> FBiOSTargetQuery {
    return self.allTargets().simulatorStates(states)
  }

  public func simulatorStates(states: [FBSimulatorState]) -> FBiOSTargetQuery {
    let indexSet = states.reduce(NSMutableIndexSet()) { (indexSet, state) in
      indexSet.addIndex(Int(state.rawValue))
      return indexSet
    }
    return self.states(indexSet)
  }

  public static func ofCount(count: Int) -> FBiOSTargetQuery {
    return self.allTargets().ofCount(count)
  }

  public func ofCount(count: Int) -> FBiOSTargetQuery {
    return self.range(NSRange(location: 0, length: count))
  }
}

extension FBiOSTargetQuery : Accumulator {
  public func append(other: FBiOSTargetQuery) -> Self {
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
  public func append(other: FBiOSTargetFormat) -> Self {
    return self.appendFields(other.fields)
  }
}

extension FBSimulatorLaunchConfiguration : Accumulator {
  public func append(other: FBSimulatorLaunchConfiguration) -> Self {
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

extension IndividualCreationConfiguration {
  public var simulatorConfiguration : FBSimulatorConfiguration { get {
    var configuration = FBSimulatorConfiguration.defaultConfiguration()
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
