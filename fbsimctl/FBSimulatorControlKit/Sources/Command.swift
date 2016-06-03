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
  Base Options that are also used in Help.
*/
public struct OutputOptions : OptionSetType {
  public let rawValue : Int
  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  public static let DebugLogging = OutputOptions(rawValue: 1 << 0)
  public static let JSON = OutputOptions(rawValue: 1 << 1)
  public static let Pretty = OutputOptions(rawValue: 1 << 2)
}

/**
  Describes the Configuration for the running FBSimulatorControl Commands
*/
public struct Configuration {
  public let outputOptions: OutputOptions
  public let managementOptions: FBSimulatorManagementOptions
  public let deviceSetPath: String?
}

/**
 Defines a the Keywords for specifying the formatting of the Simulator.
*/
public enum Keyword : String {
  case UDID = "--udid"
  case Name = "--name"
  case DeviceName = "--device-name"
  case OSVersion = "--os"
  case State = "--state"
  case ProcessIdentifier = "--pid"
}
public typealias Format = [Keyword]

/**
 Options for Creating a Server for listening to commands on.
 */
public enum Server {
  case StdIO
  case Socket(in_port_t)
  case Http(in_port_t)
}

/**
  An Enumeration specifying the output format of diagnostics.
*/
public enum DiagnosticFormat : String {
  case CurrentFormat = "--current-format"
  case Path = "--path"
  case Content = "--content"
}

/**
 An Interaction represents a Single, synchronous interaction with a Simulator.
 */
public enum Action {
  case Approve([String])
  case Boot(FBSimulatorLaunchConfiguration?)
  case ClearKeychain(String)
  case Create(FBSimulatorConfiguration)
  case Delete
  case Diagnose(FBSimulatorDiagnosticQuery, DiagnosticFormat)
  case Erase
  case Install(FBSimulatorApplication)
  case LaunchAgent(FBAgentLaunchConfiguration)
  case LaunchApp(FBApplicationLaunchConfiguration)
  case LaunchXCTest(FBApplicationLaunchConfiguration, String)
  case List
  case ListApps
  case Listen(Server)
  case Open(NSURL)
  case Record(Bool)
  case Relaunch(FBApplicationLaunchConfiguration)
  case Search(FBBatchLogSearch)
  case Shutdown
  case Tap(Double, Double)
  case Terminate(String)
  case Uninstall(String)
  case Upload([FBDiagnostic])
}

/**
 The entry point for all commands.
 */
public indirect enum Command {
  case Perform(Configuration, [Action], FBiOSTargetQuery?, Format?)
  case Help(OutputOptions, Bool, Command?)
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

  public func append(other: Configuration) -> Configuration {
    return Configuration(
      outputOptions: self.outputOptions.union(other.outputOptions),
      managementOptions: self.managementOptions.union(other.managementOptions),
      deviceSetPath: other.deviceSetPath ?? self.deviceSetPath
    )
  }

  public static func ofOutputOptions(output: OutputOptions) -> Configuration {
    let query = self.identity
    return Configuration(outputOptions: output, managementOptions: query.managementOptions, deviceSetPath: query.deviceSetPath)
  }

  public static func ofManagementOptions(managementOptions: FBSimulatorManagementOptions) -> Configuration {
    let query = self.identity
    return Configuration(outputOptions: query.outputOptions, managementOptions: managementOptions, deviceSetPath: query.deviceSetPath)
  }

  public static func ofDeviceSetPath(deviceSetPath: String) -> Configuration {
    let query = self.identity
    return Configuration(outputOptions: query.outputOptions, managementOptions: FBSimulatorManagementOptions(), deviceSetPath: deviceSetPath)
  }
}

extension Action : Equatable { }
public func == (left: Action, right: Action) -> Bool {
  switch (left, right) {
  case (.Approve(let leftBundleIDs), .Approve(let rightBundleIDs)):
    return leftBundleIDs == rightBundleIDs
  case (.Boot(let leftConfiguration), .Boot(let rightConfiguration)):
    return leftConfiguration == rightConfiguration
  case (.ClearKeychain(let leftBundleID), .ClearKeychain(let rightBundleID)):
    return leftBundleID == rightBundleID
  case (.Create(let leftConfiguration), .Create(let rightConfiguration)):
    return leftConfiguration == rightConfiguration
  case (.Delete, .Delete):
    return true
  case (.Diagnose(let leftQuery, let leftFormat), .Diagnose(let rightQuery, let rightFormat)):
    return leftQuery == rightQuery && leftFormat == rightFormat
  case (.Erase, .Erase):
    return true
  case (.Install(let leftApp), .Install(let rightApp)):
    return leftApp == rightApp
  case (.LaunchAgent(let leftLaunch), .LaunchAgent(let rightLaunch)):
    return leftLaunch == rightLaunch
  case (.LaunchApp(let leftLaunch), .LaunchApp(let rightLaunch)):
    return leftLaunch == rightLaunch
  case (.LaunchXCTest(let leftLaunch, let leftBundle), .LaunchXCTest(let rightLaunch, let rightBundle)):
    return leftLaunch == rightLaunch && leftBundle == rightBundle
  case (.List, .List):
    return true
  case (.ListApps, .ListApps):
    return true
  case (.Listen(let leftServer), .Listen(let rightServer)):
    return leftServer == rightServer
  case (.Open(let leftURL), .Open(let rightURL)):
    return leftURL == rightURL
  case (.Record(let leftStart), .Record(let rightStart)):
    return leftStart == rightStart
  case (.Relaunch(let leftLaunch), .Relaunch(let rightLaunch)):
    return leftLaunch == rightLaunch
  case (.Search(let leftSearch), .Search(let rightSearch)):
    return leftSearch == rightSearch
  case (.Shutdown, .Shutdown):
    return true
  case (.Tap(let leftX, let leftY), .Tap(let rightX, let rightY)):
    return leftX == rightX && leftY == rightY
  case (.Terminate(let leftBundleID), .Terminate(let rightBundleID)):
    return leftBundleID == rightBundleID
  case (.Uninstall(let leftBundleID), .Uninstall(let rightBundleID)):
    return leftBundleID == rightBundleID
  case (.Upload(let leftPaths), .Upload(let rightPaths)):
    return leftPaths == rightPaths
  default:
    return false
  }
}

extension Command : Equatable {}
public func == (left: Command, right: Command) -> Bool {
  switch (left, right) {
  case (.Perform(let leftConfiguration, let leftActions, let leftQuery, let leftMaybeFormat), .Perform(let rightConfiguration, let rightActions, let rightQuery, let rightMaybeFormat)):
    if leftConfiguration != rightConfiguration || leftActions != rightActions || leftQuery != rightQuery {
      return false
    }

    // The == function isn't as concise as it could be as Format? isn't automatically Equatable
    // This is despite [Equatable] Equatable? and Format all being Equatable
    switch (leftMaybeFormat, rightMaybeFormat) {
    case (.Some(let leftFormat), .Some(let rightFormat)):
      return leftFormat == rightFormat
    case (.None, .None):
      return true
    default:
      return false
    }
  case (.Help(let leftOutput, let leftSuccess, let leftCommand), .Help(let rightOutput, let rightSuccess, let rightCommand)):
    return leftOutput == rightOutput && leftSuccess == rightSuccess && leftCommand == rightCommand
  default:
    return false
  }
}

extension Server : Equatable { }
public func == (left: Server, right: Server) -> Bool {
  switch (left, right) {
  case (.StdIO, .StdIO):
    return true
  case (.Socket(let leftPort), .Socket(let rightPort)):
    return leftPort == rightPort
  case (.Http(let leftPort), .Http(let rightPort)):
    return leftPort == rightPort
  default:
    return false
  }
}

extension Server : JSONDescribeable, CustomStringConvertible {
  public var jsonDescription: JSON {
    get {
      switch self {
      case .StdIO:
        return JSON.JDictionary([
          "type" : JSON.JString("stdio")
        ])
      case .Socket(let port):
        return JSON.JDictionary([
          "type" : JSON.JString("socket"),
          "port" : JSON.JNumber(NSNumber(int: Int32(port)))
        ])
      case .Http(let port):
        return JSON.JDictionary([
          "type" : JSON.JString("http"),
          "port" : JSON.JNumber(NSNumber(int: Int32(port)))
        ])
      }
    }
  }

  public var description: String {
    get {
      switch self {
      case .StdIO: return "stdio"
      case .Socket(let port): return "Socket: Port \(port)"
      case .Http(let port): return "HTTP: Port \(port)"
      }
    }
  }
}
