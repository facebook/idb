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
 Options for Listening on an Interface.
 */
public struct ListenInterface {
  let stdin: Bool
  let http: in_port_t?
  let hid: in_port_t?
  let handle: FBTerminationHandle?
}

/**
 A Configuration for Creating an Individual Simulator.
 */
public struct IndividualCreationConfiguration {
  let os: FBOSVersionName?
  let model: FBDeviceModel?
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
 An Enumeration for controlling recording.
 */
public enum Record {
  case start(String?)
  case stop
}

public enum FileOutput {
  case path(String)
  case standardOut
}

/**
 An Interaction represents a Single, synchronous interaction with a Simulator.
 */
public enum Action {
  case approve([String])
  case clearKeychain(String?)
  case config
  case core(FBiOSTargetAction)
  case create(CreationSpecification)
  case delete
  case diagnose(FBDiagnosticQuery, DiagnosticFormat)
  case erase
  case focus
  case install(String, Bool)
  case keyboardOverride
  case list
  case listApps
  case listDeviceSets
  case listen(ListenInterface)
  case open(URL)
  case record(Record)
  case relaunch(FBApplicationLaunchConfiguration)
  case search(FBBatchLogSearch)
  case serviceInfo(String)
  case setLocation(Double,Double)
  case shutdown
  case stream(FBBitmapStreamConfiguration, FileOutput)
  case terminate(String)
  case uninstall(String)
  case upload([FBDiagnostic])
  case watchdogOverride([String], TimeInterval)

  static func boot(_ configuration: FBSimulatorBootConfiguration) -> Action {
    return self.core(configuration)
  }

  static func hid(_ event: FBSimulatorHIDEvent) -> Action {
    return self.core(event)
  }

  static func launchApp(_ appLaunch: FBApplicationLaunchConfiguration) -> Action {
    return self.core(appLaunch)
  }

  static func launchAgent(_ agentLaunch: FBAgentLaunchConfiguration) -> Action {
    return self.core(agentLaunch)
  }

  static func launchXCTest(_ testLaunch: FBTestLaunchConfiguration) -> Action {
    return self.core(testLaunch.withUITesting(true))
  }
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

extension ListenInterface : Equatable {}
public func == (left: ListenInterface, right: ListenInterface) -> Bool {
  return left.stdin == right.stdin && left.http == right.http && left.hid == right.hid
}

extension ListenInterface : Accumulator {
  public init() {
    self.stdin = false
    self.http = nil
    self.hid = nil
    self.handle = nil
  }

  public static var identity: ListenInterface { get {
    return ListenInterface()
  }}

  public func append(_ other: ListenInterface) -> ListenInterface {
    return ListenInterface(
      stdin: other.stdin ? other.stdin : self.stdin,
      http: other.http ?? self.http,
      hid: other.hid ?? self.hid,
      handle: other.handle ?? self.handle
    )
  }
}

extension FBTerminationHandleType {
  var listenDescription: String? { get {
    switch self {
      case FBTerminationHandleType.typeHandleVideoRecording:
        return "Recording Video"
      case FBTerminationHandleType.videoStreaming:
        return "Streaming Video"
      case FBTerminationHandleType.testOperation:
        return "Test Operation"
      case FBTerminationHandleType.actionReader:
        return "Action Reader"
      default:
        return nil
    }
  }}
}

extension ListenInterface : EventReporterSubject {
  public var jsonDescription: JSON { get {
    var httpValue = JSON.null
    if let portNumber = self.http {
      httpValue = JSON.number(NSNumber(integerLiteral: Int(portNumber)))
    }
    var hidValue = JSON.null
    if let portNumber = self.hid {
      hidValue = JSON.number(NSNumber(integerLiteral: Int(portNumber)))
    }
    var handleValue = JSON.null
    if let handle = self.handle {
      handleValue = JSON.string(type(of: handle).handleType.rawValue)
    }

    return JSON.dictionary([
      "stdin" : JSON.bool(self.stdin),
      "http" : httpValue,
      "hid" : hidValue,
      "handle" : handleValue,
    ])
  }}

  public var description: String { get {
    if let listenDescription = self.listenDescription {
      return listenDescription
    }
    var description = "Http: "
    if let httpPort = self.http {
      description += httpPort.description
    } else {
      description += "No"
    }
    description += " Hid: "
    if let hidPort = self.hid {
      description += hidPort.description
    } else {
      description += "No"
    }
    description += " stdin: \(self.stdin)"
    if let handle = self.handle {
      description += " due to \(type(of: handle).handleType.rawValue)"
    }
    return description
  }}

  private var listenDescription: String? { get {
    if !self.isEmptyListen {
      return nil
    }
    guard  let handle = self.handle else {
      return nil
    }
    return type(of: handle).handleType.listenDescription
  }}

  var isEmptyListen: Bool { get {
    return self.stdin == false && self.http == nil && self.hid == nil
  }}
}

extension IndividualCreationConfiguration : Equatable {}
public func == (left: IndividualCreationConfiguration, right: IndividualCreationConfiguration) -> Bool {
  return left.os == right.os &&
         left.model == right.model &&
         left.auxDirectory == right.auxDirectory
}

extension IndividualCreationConfiguration : Accumulator {
  public init() {
    self.os = nil
    self.model = nil
    self.auxDirectory = nil
  }

  public func append(_ other: IndividualCreationConfiguration) -> IndividualCreationConfiguration {
    return IndividualCreationConfiguration(
      os: other.os ?? self.os,
      model: other.model ?? self.model,
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

extension Record : Equatable {}
public func == (left: Record, right: Record) -> Bool {
  switch (left, right) {
  case (.start(let leftPath), .start(let rightPath)):
    return leftPath == rightPath
  case (.stop, .stop):
    return true
  default:
    return false
  }
}

extension FileOutput : Equatable {}
public func == (left: FileOutput, right: FileOutput) -> Bool {
  switch (left, right) {
  case (.path(let leftPath), .path(let rightPath)):
    return leftPath == rightPath
  case (.standardOut, .standardOut):
    return true
  default:
    return false
  }
}

extension Action : Equatable { }
public func == (left: Action, right: Action) -> Bool {
  switch (left, right) {
  case (.approve(let leftBundleIDs), .approve(let rightBundleIDs)):
    return leftBundleIDs == rightBundleIDs
  case (.clearKeychain(let leftBundleID), .clearKeychain(let rightBundleID)):
    return leftBundleID == rightBundleID
  case (.config, .config):
    return true
  case (.core(let leftAction), .core(let rightAction)):
    return leftAction.isEqual(rightAction)
  case (.create(let leftSpecification), .create(let rightSpecification)):
    return leftSpecification == rightSpecification
  case (.delete, .delete):
    return true
  case (.diagnose(let leftQuery, let leftFormat), .diagnose(let rightQuery, let rightFormat)):
    return leftQuery == rightQuery && leftFormat == rightFormat
  case (.erase, .erase):
    return true
  case (.focus, .focus):
    return true
  case (.install(let leftApp, let leftSign), .install(let rightApp, let rightSign)):
    return leftApp == rightApp && leftSign == rightSign
  case (.keyboardOverride, .keyboardOverride):
    return true
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
  case (.stream(let leftConfiguration, let leftOutput), .stream(let rightConfiguration, let rightOutput)):
    return leftConfiguration == rightConfiguration && leftOutput == rightOutput
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
      return (.approve, StringsSubject(bundleIDs))
    case .clearKeychain(let bundleID):
      return (.clearKeychain, bundleID)
    case .config:
      return (.config, nil)
    case .core(let action):
      return (action.eventName, ControlCoreSubject(action as! ControlCoreValue))
    case .create:
      return (.create, nil)
    case .delete:
      return (.delete, nil)
    case .diagnose(let query, _):
      return (.diagnose, ControlCoreSubject(query))
    case .erase:
      return (.erase, nil)
    case .focus:
      return (.focus, nil)
    case .install:
      return (.install, nil)
    case .keyboardOverride:
      return (.keyboardOverride, nil)
    case .list:
        return (.list, nil)
    case .listApps:
      return (.listApps, nil)
    case .listDeviceSets:
      return (.listDeviceSets, nil)
    case .listen:
      return (.listen, nil)
    case .open(let url):
      return (.open, url.absoluteString)
    case .record(let record):
      return (.record, record)
    case .relaunch(let appLaunch):
      return (.relaunch, ControlCoreSubject(appLaunch))
    case .search(let search):
      return (.search, ControlCoreSubject(search))
    case .serviceInfo:
      return (.serviceInfo, nil)
    case .setLocation:
      return (.setLocation, nil)
    case .shutdown:
      return (.shutdown, nil)
    case .stream:
      return (.stream, nil)
    case .terminate(let bundleID):
      return (.terminate, bundleID)
    case .uninstall(let bundleID):
      return (.uninstall, bundleID)
    case .upload:
      return (.diagnose, nil)
    case .watchdogOverride(let bundleIDs, _):
      return (.watchdogOverride, StringsSubject(bundleIDs))
    }
  }}
}
