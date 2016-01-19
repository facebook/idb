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

/**
  Describes the Configuration for the running of a Command
*/
public struct Configuration {
  public struct Options : OptionSetType {
    public let rawValue : Int
    public init(rawValue: Int) {
      self.rawValue = rawValue
    }

    static let DebugLogging = Options(rawValue: 1 << 0)
    static let JSONOutput = Options(rawValue: 1 << 1)
  }

  let controlConfiguration: FBSimulatorControlConfiguration
  let options: Options
}

/**
 Defines a Format for displaying Simulator Information
*/
public indirect enum Format {
  case UDID
  case Name
  case DeviceName
  case OSVersion
  case State
  case ProcessIdentifier
  case Compound([Format])
}

/**
 An Interaction represents a Single, synchronous interaction with a Simulator.
 */
public enum Interaction {
  case List
  case Approve([String])
  case Boot(FBSimulatorLaunchConfiguration?)
  case Shutdown
  case Diagnose
  case Delete
  case Install(FBSimulatorApplication)
  case Launch(FBProcessLaunchConfiguration)
}

/**
 An Action represents either:
 1) An Interaction with a Query of Simulators and a Format of textual output.
 2) The Creation of a Simulator based on a FBSimulatorConfiguration and Format textual output.
*/
public enum Action {
  case Interact([Interaction], Query?, Format?)
  case Create(FBSimulatorConfiguration, Format?)
}

/**
 The entry point for all commands.
 */
public enum Command {
  case Perform(Configuration, Action)
  case Interactive(Configuration, Int?)
  case Help(Interaction?)
}

public extension Format {
  static func flatten(formats: [Format]) -> Format {
    if (formats.count == 1) {
      return formats.first!
    }

    return .Compound(formats)
  }
}

extension Configuration : Equatable {}
public func == (left: Configuration, right: Configuration) -> Bool {
  return left.options == right.options && left.controlConfiguration == right.controlConfiguration
}

extension Command : Equatable {}
public func == (left: Command, right: Command) -> Bool {
  switch (left, right) {
  case (.Perform(let leftConfiguration, let lefts), .Perform(let rightConfiguration, let rights)):
    return leftConfiguration == rightConfiguration && lefts == rights
  case (.Interactive(let leftConfiguration, let leftPort), .Interactive(let rightConfiguration, let rightPort)):
    return leftConfiguration == rightConfiguration && leftPort == rightPort
  case (.Help(let left), .Help(let right)):
    return left == right
  default:
    return false
  }
}

extension Action : Equatable { }
public func == (left: Action, right: Action) -> Bool {
  switch (left, right) {
    case (.Interact(let leftInteractions, let leftQuery, let leftFormat), .Interact(let rightInteractions, let rightQuery, let rightFormat)):
      return leftInteractions == rightInteractions && leftQuery == rightQuery && leftFormat == rightFormat
    case (.Create(let leftConfiguration, let leftFormat), .Create(let rightConfiguration, let rightFormat)):
      return leftConfiguration == rightConfiguration && leftFormat == rightFormat
    default:
      return true
  }
}

extension Interaction : Equatable { }
public func == (left: Interaction, right: Interaction) -> Bool {
  switch (left, right) {
  case (.List, .List):
    return true
  case (.Approve(let leftBundleIDs), .Approve(let rightBundleIDs)):
    return leftBundleIDs == rightBundleIDs
  case (.Boot(let leftConfiguration), .Boot(let rightConfiguration)):
    return leftConfiguration == rightConfiguration
  case (.Shutdown, .Shutdown):
    return true
  case (.Diagnose, .Diagnose):
    return true
  case (.Delete, .Delete):
    return true
  case (.Install(let leftApp), .Install(let rightApp)):
    return leftApp == rightApp
  case (.Launch(let leftLaunch), .Launch(let rightLaunch)):
    return leftLaunch == rightLaunch
  default:
    return false
  }
}

extension Format : Equatable { }
public func == (left: Format, right: Format) -> Bool {
  switch (left, right) {
  case (.UDID, .UDID): return true
  case (.OSVersion, .OSVersion): return true
  case (.DeviceName, .DeviceName): return true
  case (.Name, .Name): return true
  case (.State, .State): return true
  case (.ProcessIdentifier, .ProcessIdentifier): return true
  case (.Compound(let leftComp), .Compound(let rightComp)): return leftComp == rightComp
  default: return false
  }
}

extension Format : Hashable {
  public var hashValue: Int {
    get {
      switch self {
      case .UDID:
        return 1 << 0
      case .OSVersion:
        return 1 << 1
      case .DeviceName:
        return 1 << 2
      case .Name:
        return 1 << 3
      case .State:
        return 1 << 4
      case .ProcessIdentifier:
        return 1 << 5
      case .Compound(let format):
        return format.reduce("compound".hashValue) { previous, next in
          return previous ^ next.hashValue
        }
      }
    }
  }
}
