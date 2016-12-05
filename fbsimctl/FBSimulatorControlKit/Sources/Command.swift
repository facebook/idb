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
import FBControlCore

/**
  Describes the Configuration for the running FBSimulatorControl Commands
*/
public struct Configuration {
  public let outputOptions: OutputOptions
  public let managementOptions: FBSimulatorManagementOptions
  public let deviceSetPath: String?
}

/**
 Options for Creating a Server for listening to commands on.
 */
public enum Server {
  case empty
  case stdin
  case http(in_port_t)
}

/**
 A Configuration for Creating an Individual Simulator.
 */
public struct IndividualCreationConfiguration {
  let osVersion: FBControlCoreConfiguration_OS?
  let deviceType: FBControlCoreConfiguration_Device?
  let auxDirectory : String?
}

/**
 A Specification for the 'Create' Action.
 */
public enum CreationSpecification {
  case allMissingDefaults
  case individual(IndividualCreationConfiguration)
}

/**
  An Enumeration specifying the output format of diagnostics.
*/
public enum DiagnosticFormat : String {
  case CurrentFormat = "current-format"
  case Path = "path"
  case Content = "content"
}

/**
 An Interaction represents a Single, synchronous interaction with a Simulator.
 */
public enum Action {
  case approve([String])
  case boot(FBSimulatorBootConfiguration?)
  case clearKeychain(String?)
  case config
  case create(CreationSpecification)
  case delete
  case diagnose(FBDiagnosticQuery, DiagnosticFormat)
  case erase
  case install(String)
  case keyboardOverride
  case launchAgent(FBAgentLaunchConfiguration)
  case launchApp(FBApplicationLaunchConfiguration)
  case launchXCTest(FBTestLaunchConfiguration)
  case list
  case listApps
  case listDeviceSets
  case listen(Server)
  case open(URL)
  case record(Bool)
  case relaunch(FBApplicationLaunchConfiguration)
  case search(FBBatchLogSearch)
  case serviceInfo(String)
  case setLocation(Double,Double)
  case shutdown
  case tap(Double, Double)
  case terminate(String)
  case uninstall(String)
  case upload([FBDiagnostic])
  case watchdogOverride([String], TimeInterval)
}

/**
 Some Actions performed on some targets.
 */
public struct Command {
  let configuration: Configuration
  let actions: [Action]
  let query: FBiOSTargetQuery?
  let format: FBiOSTargetFormat?
}

extension Command : Equatable {}
public func == (left: Command, right: Command) -> Bool {
  return left.configuration == right.configuration && left.actions == right.actions && left.query == right.query && left.format == right.format
}

extension Configuration : Equatable {}
public func == (left: Configuration, right: Configuration) -> Bool {
  return left.outputOptions == right.outputOptions && left.deviceSetPath == right.deviceSetPath && left.managementOptions == right.managementOptions
}

extension Configuration : Accumulator {
  public init() {
    self.outputOptions = OutputOptions()
    self.managementOptions = FBSimulatorManagementOptions()
    self.deviceSetPath = nil
  }

  public static var identity: Configuration { get {
    return Configuration.defaultValue
  }}

  public func append(_ other: Configuration) -> Configuration {
    return Configuration(
      outputOptions: self.outputOptions.union(other.outputOptions),
      managementOptions: self.managementOptions.union(other.managementOptions),
      deviceSetPath: other.deviceSetPath ?? self.deviceSetPath
    )
  }

  public static func ofOutputOptions(_ output: OutputOptions) -> Configuration {
    let query = self.identity
    return Configuration(outputOptions: output, managementOptions: query.managementOptions, deviceSetPath: query.deviceSetPath)
  }

  public static func ofManagementOptions(_ managementOptions: FBSimulatorManagementOptions) -> Configuration {
    let query = self.identity
    return Configuration(outputOptions: query.outputOptions, managementOptions: managementOptions, deviceSetPath: query.deviceSetPath)
  }

  public static func ofDeviceSetPath(_ deviceSetPath: String) -> Configuration {
    let query = self.identity
    return Configuration(outputOptions: query.outputOptions, managementOptions: FBSimulatorManagementOptions(), deviceSetPath: deviceSetPath)
  }
}

extension IndividualCreationConfiguration : Equatable {}
public func == (left: IndividualCreationConfiguration, right: IndividualCreationConfiguration) -> Bool {
  return left.osVersion?.name == right.osVersion?.name &&
         left.deviceType?.deviceName == right.deviceType?.deviceName &&
         left.auxDirectory == right.auxDirectory
}

extension IndividualCreationConfiguration : Accumulator {
  public init() {
    self.osVersion = nil
    self.deviceType = nil
    self.auxDirectory = nil
  }

  public func append(_ other: IndividualCreationConfiguration) -> IndividualCreationConfiguration {
    return IndividualCreationConfiguration(
      osVersion: other.osVersion ?? self.osVersion,
      deviceType: other.deviceType ?? self.deviceType,
      auxDirectory: other.auxDirectory ?? self.auxDirectory
    )
  }
}

extension CreationSpecification : Equatable {}
public func == (left: CreationSpecification, right: CreationSpecification) -> Bool {
  switch (left, right) {
  case (.allMissingDefaults, .allMissingDefaults):
    return true
  case (.individual(let leftConfiguration), .individual(let rightConfiguration)):
    return leftConfiguration == rightConfiguration
  default:
    return false
  }
}

extension Action : Equatable { }
public func == (left: Action, right: Action) -> Bool {
  switch (left, right) {
  case (.approve(let leftBundleIDs), .approve(let rightBundleIDs)):
    return leftBundleIDs == rightBundleIDs
  case (.boot(let leftConfiguration), .boot(let rightConfiguration)):
    return leftConfiguration == rightConfiguration
  case (.clearKeychain(let leftBundleID), .clearKeychain(let rightBundleID)):
    return leftBundleID == rightBundleID
  case (.config, .config):
    return true
  case (.create(let leftSpecification), .create(let rightSpecification)):
    return leftSpecification == rightSpecification
  case (.delete, .delete):
    return true
  case (.diagnose(let leftQuery, let leftFormat), .diagnose(let rightQuery, let rightFormat)):
    return leftQuery == rightQuery && leftFormat == rightFormat
  case (.erase, .erase):
    return true
  case (.install(let leftApp), .install(let rightApp)):
    return leftApp == rightApp
  case (.keyboardOverride, .keyboardOverride):
    return true
  case (.launchAgent(let leftLaunch), .launchAgent(let rightLaunch)):
    return leftLaunch == rightLaunch
  case (.launchApp(let leftLaunch), .launchApp(let rightLaunch)):
    return leftLaunch == rightLaunch
  case (.launchXCTest(let leftConfiguration), .launchXCTest(let rightConfiguration)):
    return leftConfiguration == rightConfiguration
  case (.list, .list):
    return true
  case (.listApps, .listApps):
    return true
  case (.listDeviceSets, .listDeviceSets):
    return true
  case (.listen(let leftServer), .listen(let rightServer)):
    return leftServer == rightServer
  case (.open(let leftURL), .open(let rightURL)):
    return leftURL == rightURL
  case (.record(let leftStart), .record(let rightStart)):
    return leftStart == rightStart
  case (.relaunch(let leftLaunch), .relaunch(let rightLaunch)):
    return leftLaunch == rightLaunch
  case (.search(let leftSearch), .search(let rightSearch)):
    return leftSearch == rightSearch
  case (.serviceInfo(let leftIdentifier), .serviceInfo(let rightIdentifier)):
    return leftIdentifier == rightIdentifier
  case (.setLocation(let leftLat, let leftLon), .setLocation(let rightLat, let rightLon)):
    return leftLat == rightLat && leftLon == rightLon
  case (.shutdown, .shutdown):
    return true
  case (.tap(let leftX, let leftY), .tap(let rightX, let rightY)):
    return leftX == rightX && leftY == rightY
  case (.terminate(let leftBundleID), .terminate(let rightBundleID)):
    return leftBundleID == rightBundleID
  case (.uninstall(let leftBundleID), .uninstall(let rightBundleID)):
    return leftBundleID == rightBundleID
  case (.upload(let leftPaths), .upload(let rightPaths)):
    return leftPaths == rightPaths
  case (.watchdogOverride(let leftBundleIDs, let leftTimeout), .watchdogOverride(let rightBundleIDs, let rightTimeout)):
    return leftBundleIDs == rightBundleIDs && leftTimeout == rightTimeout
  default:
    return false
  }
}

extension Action {
  public var reportable: (EventName, EventReporterSubject?) { get {
    switch self {
    case .approve(let bundleIDs):
      return (EventName.Approve, StringsSubject(bundleIDs))
    case .boot:
      return (EventName.Boot, nil)
    case .clearKeychain(let bundleID):
      return (EventName.ClearKeychain, bundleID)
    case .config:
      return (EventName.Config, nil)
    case .create:
      return (EventName.Create, nil)
    case .delete:
      return (EventName.Delete, nil)
    case .diagnose(let query, _):
      return (EventName.Diagnose, ControlCoreSubject(query))
    case .erase:
      return (EventName.Erase, nil)
    case .install:
      return (EventName.Install, nil)
    case .keyboardOverride:
      return (EventName.KeyboardOverride, nil)
    case .launchAgent(let launch):
      return (EventName.Launch, ControlCoreSubject(launch))
    case .launchApp(let launch):
      return (EventName.Launch, ControlCoreSubject(launch))
    case .launchXCTest(let configuration):
        return (EventName.LaunchXCTest, ControlCoreSubject(configuration))
    case .list:
        return (EventName.List, nil)
    case .listApps:
      return (EventName.ListApps, nil)
    case .listDeviceSets:
      return (EventName.ListDeviceSets, nil)
    case .listen:
      return (EventName.Listen, nil)
    case .open(let url):
      return (EventName.Open, url.absoluteString)
    case .record(let start):
      return (EventName.Record, start)
    case .relaunch(let appLaunch):
      return (EventName.Relaunch, ControlCoreSubject(appLaunch))
    case .search(let search):
      return (EventName.Search, ControlCoreSubject(search))
    case .serviceInfo:
      return (EventName.ServiceInfo, nil)
    case .setLocation:
      return (EventName.SetLocation, nil)
    case .shutdown:
      return (EventName.Shutdown, nil)
    case .tap:
      return (EventName.Tap, nil)
    case .terminate(let bundleID):
      return (EventName.Terminate, bundleID)
    case .uninstall(let bundleID):
      return (EventName.Uninstall, bundleID)
    case .upload:
      return (EventName.Diagnose, nil)
    case .watchdogOverride(let bundleIDs, _):
      return (EventName.WatchdogOverride, StringsSubject(bundleIDs))
    }
  }}
}

extension Server : Equatable { }
public func == (left: Server, right: Server) -> Bool {
  switch (left, right) {
  case (.empty, .empty):
    return true
  case (.stdin, .stdin):
    return true
  case (.http(let leftPort), .http(let rightPort)):
    return leftPort == rightPort
  default:
    return false
  }
}

extension Server : EventReporterSubject {
  public var jsonDescription: JSON { get {
    switch self {
    case .empty:
      return JSON.jDictionary([
        "type" : JSON.jString("empty")
      ])
    case .stdin:
      return JSON.jDictionary([
        "type" : JSON.jString("stdin")
      ])
    case .http(let port):
      return JSON.jDictionary([
        "type" : JSON.jString("http"),
        "port" : JSON.jNumber(NSNumber(value: Int32(port) as Int32))
      ])
    }
  }}

  public var description: String { get {
    switch self {
    case .empty: return "empty"
    case .stdin: return "stdin"
    case .http(let port): return "HTTP: Port \(port)"
    }
  }}
}
