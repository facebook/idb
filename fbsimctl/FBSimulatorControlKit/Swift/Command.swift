/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBSimulatorControl
import Foundation

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
  let continuation: FBiOSTargetContinuation?

  var isEmptyListen: Bool {
    return stdin == false && http == nil && hid == nil
  }
}

/**
 A Configuration for Creating an Individual Simulator.
 */
public struct IndividualCreationConfiguration {
  let os: FBOSVersionName?
  let model: FBDeviceModel?
  let auxDirectory: String?
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
public typealias DiagnosticFormat = FBDiagnosticQueryFormat

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
  case clearKeychain(String?)
  case config
  case coreFuture(FBiOSTargetFuture)
  case create(CreationSpecification)
  case clone
  case delete
  case focus
  case keyboardOverride
  case list
  case listDeviceSets
  case listen(ListenInterface)
  case open(URL)
  case record(Record)
  case relaunch(FBApplicationLaunchConfiguration)
  case setLocation(Double, Double)
  case stream(FBBitmapStreamConfiguration, FileOutput)
  case terminate(String)
  case uninstall(String)
  case upload([FBDiagnostic])
  case watchdogOverride([String], TimeInterval)

  static var accessibility: Action {
    return coreFuture(FBAccessibilityFetch())
  }

  static func approve(_ bundleIDs: [String]) -> Action {
    return coreFuture(FBSettingsApproval(bundleIDs: bundleIDs, services: [.location]))
  }

  static func boot(_ configuration: FBSimulatorBootConfiguration) -> Action {
    return coreFuture(configuration)
  }

  static func contactsUpdate(_ databaseDirectory: String) -> Action {
    return coreFuture(FBContactsUpdateConfiguration(databaseDirectory: databaseDirectory))
  }

  static func diagnose(_ query: FBDiagnosticQuery) -> Action {
    return coreFuture(query)
  }

  static var erase: Action {
    return coreFuture(FBSimulatorEraseConfiguration())
  }

  static func hid(_ event: FBSimulatorHIDEvent) -> Action {
    return coreFuture(event)
  }

  static func install(_ path: String, _ codesign: Bool) -> Action {
    return coreFuture(FBApplicationInstallConfiguration.applicationInstall(withPath: path, codesign: codesign))
  }

  static func launchApp(_ appLaunch: FBApplicationLaunchConfiguration) -> Action {
    return coreFuture(appLaunch)
  }

  static func launchAgent(_ agentLaunch: FBAgentLaunchConfiguration) -> Action {
    return coreFuture(agentLaunch)
  }

  static func launchXCTest(_ testLaunch: FBTestLaunchConfiguration) -> Action {
    return coreFuture(testLaunch.withUITesting(true))
  }

  static var listApps: Action {
    return coreFuture(FBListApplicationsConfiguration())
  }

  static func logTail(_ configuration: FBLogTailConfiguration) -> Action {
    return coreFuture(configuration)
  }

  static func search(_ search: FBBatchLogSearch) -> Action {
    return coreFuture(search)
  }

  static func serviceInfo(_ serviceName: String) -> Action {
    return coreFuture(FBServiceInfoConfiguration(serviceName: serviceName))
  }

  static var shutdown: Action {
    return coreFuture(FBShutdownConfiguration())
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

extension Command: Equatable {}
public func == (left: Command, right: Command) -> Bool {
  return left.configuration == right.configuration && left.actions == right.actions && left.query == right.query && left.format == right.format
}

extension Configuration: Equatable {}
public func == (left: Configuration, right: Configuration) -> Bool {
  return left.outputOptions == right.outputOptions && left.deviceSetPath == right.deviceSetPath && left.managementOptions == right.managementOptions
}

extension Configuration: Accumulator {
  public init() {
    outputOptions = OutputOptions()
    managementOptions = FBSimulatorManagementOptions()
    deviceSetPath = nil
  }

  public static var identity: Configuration {
    return Configuration.defaultValue
  }

  public func append(_ other: Configuration) -> Configuration {
    return Configuration(
      outputOptions: outputOptions.union(other.outputOptions),
      managementOptions: managementOptions.union(other.managementOptions),
      deviceSetPath: other.deviceSetPath ?? deviceSetPath
    )
  }

  public static func ofOutputOptions(_ output: OutputOptions) -> Configuration {
    let query = identity
    return Configuration(outputOptions: output, managementOptions: query.managementOptions, deviceSetPath: query.deviceSetPath)
  }

  public static func ofManagementOptions(_ managementOptions: FBSimulatorManagementOptions) -> Configuration {
    let query = identity
    return Configuration(outputOptions: query.outputOptions, managementOptions: managementOptions, deviceSetPath: query.deviceSetPath)
  }

  public static func ofDeviceSetPath(_ deviceSetPath: String) -> Configuration {
    let query = identity
    return Configuration(outputOptions: query.outputOptions, managementOptions: FBSimulatorManagementOptions(), deviceSetPath: deviceSetPath)
  }
}

extension ListenInterface: Equatable {}
public func == (left: ListenInterface, right: ListenInterface) -> Bool {
  return left.stdin == right.stdin && left.http == right.http && left.hid == right.hid
}

extension ListenInterface: Accumulator {
  public init() {
    stdin = false
    http = nil
    hid = nil
    continuation = nil
  }

  public static var identity: ListenInterface {
    return ListenInterface()
  }

  public func append(_ other: ListenInterface) -> ListenInterface {
    return ListenInterface(
      stdin: other.stdin ? other.stdin : stdin,
      http: other.http ?? http,
      hid: other.hid ?? hid,
      continuation: other.continuation ?? continuation
    )
  }
}

extension FBiOSTargetFutureType {
  var listenDescription: String? {
    switch self {
    case FBiOSTargetFutureType.videoRecording:
      return "Recording Video"
    case FBiOSTargetFutureType.videoStreaming:
      return "Streaming Video"
    case FBiOSTargetFutureType.testOperation:
      return "Test Operation"
    case FBiOSTargetFutureType.actionReader:
      return "Action Reader"
    default:
      return nil
    }
  }
}

extension IndividualCreationConfiguration: Equatable {}
public func == (left: IndividualCreationConfiguration, right: IndividualCreationConfiguration) -> Bool {
  return left.os == right.os &&
    left.model == right.model &&
    left.auxDirectory == right.auxDirectory
}

extension IndividualCreationConfiguration: Accumulator {
  public init() {
    os = nil
    model = nil
    auxDirectory = nil
  }

  public func append(_ other: IndividualCreationConfiguration) -> IndividualCreationConfiguration {
    return IndividualCreationConfiguration(
      os: other.os ?? os,
      model: other.model ?? model,
      auxDirectory: other.auxDirectory ?? auxDirectory
    )
  }
}

extension CreationSpecification: Equatable {}
public func == (left: CreationSpecification, right: CreationSpecification) -> Bool {
  switch (left, right) {
  case (.allMissingDefaults, .allMissingDefaults):
    return true
  case let (.individual(leftConfiguration), .individual(rightConfiguration)):
    return leftConfiguration == rightConfiguration
  default:
    return false
  }
}

extension Record: Equatable {}
public func == (left: Record, right: Record) -> Bool {
  switch (left, right) {
  case let (.start(leftPath), .start(rightPath)):
    return leftPath == rightPath
  case (.stop, .stop):
    return true
  default:
    return false
  }
}

extension FileOutput: Equatable {}
public func == (left: FileOutput, right: FileOutput) -> Bool {
  switch (left, right) {
  case let (.path(leftPath), .path(rightPath)):
    return leftPath == rightPath
  case (.standardOut, .standardOut):
    return true
  default:
    return false
  }
}

extension Action: Equatable {}
public func == (left: Action, right: Action) -> Bool {
  switch (left, right) {
  case let (.clearKeychain(leftBundleID), .clearKeychain(rightBundleID)):
    return leftBundleID == rightBundleID
  case (.clone, .clone):
    return true
  case (.config, .config):
    return true
  case let (.coreFuture(leftAction), .coreFuture(rightAction)):
    return leftAction.isEqual(rightAction)
  case let (.create(leftSpecification), .create(rightSpecification)):
    return leftSpecification == rightSpecification
  case (.delete, .delete):
    return true
  case (.focus, .focus):
    return true
  case (.keyboardOverride, .keyboardOverride):
    return true
  case (.list, .list):
    return true
  case (.listDeviceSets, .listDeviceSets):
    return true
  case let (.listen(leftServer), .listen(rightServer)):
    return leftServer == rightServer
  case let (.open(leftURL), .open(rightURL)):
    return leftURL == rightURL
  case let (.record(leftStart), .record(rightStart)):
    return leftStart == rightStart
  case let (.relaunch(leftLaunch), .relaunch(rightLaunch)):
    return leftLaunch == rightLaunch
  case let (.setLocation(leftLat, leftLon), .setLocation(rightLat, rightLon)):
    return leftLat == rightLat && leftLon == rightLon
  case let (.stream(leftConfiguration, leftOutput), .stream(rightConfiguration, rightOutput)):
    return leftConfiguration == rightConfiguration && leftOutput == rightOutput
  case let (.terminate(leftBundleID), .terminate(rightBundleID)):
    return leftBundleID == rightBundleID
  case let (.uninstall(leftBundleID), .uninstall(rightBundleID)):
    return leftBundleID == rightBundleID
  case let (.upload(leftPaths), .upload(rightPaths)):
    return leftPaths == rightPaths
  case let (.watchdogOverride(leftBundleIDs, leftTimeout), .watchdogOverride(rightBundleIDs, rightTimeout)):
    return leftBundleIDs == rightBundleIDs && leftTimeout == rightTimeout
  default:
    return false
  }
}

extension Action {
  public var reportable: (EventName, EventReporterSubject?) {
    switch self {
    case .clone:
      return (.clone, nil)
    case let .clearKeychain(bundleID):
      return (.clearKeychain, FBEventReporterSubject(string: bundleID ?? "none"))
    case .config:
      return (.config, nil)
    case let .coreFuture(action):
      return (action.eventName, action.subject)
    case .create:
      return (.create, nil)
    case .delete:
      return (.delete, nil)
    case .focus:
      return (.focus, nil)
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
    case let .open(url):
      return (.open, FBEventReporterSubject(string: url.absoluteString))
    case let .record(record):
      return (.record, RecordSubject(record))
    case let .relaunch(appLaunch):
      return (.relaunch, appLaunch.subject)
    case .setLocation:
      return (.setLocation, nil)
    case .stream:
      return (.stream, nil)
    case let .terminate(bundleID):
      return (.terminate, FBEventReporterSubject(string: bundleID))
    case let .uninstall(bundleID):
      return (.uninstall, FBEventReporterSubject(string: bundleID))
    case .upload:
      return (.diagnose, nil)
    case .watchdogOverride(let bundleIDs, _):
      return (.watchdogOverride, FBEventReporterSubject(strings: bundleIDs))
    }
  }
}
