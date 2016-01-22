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
  }

  let controlConfiguration: FBSimulatorControlConfiguration
  let options: Options
}

/**
 Defines a Format for displaying Simulator Information
*/
public enum Format {
  public enum Keywords: String {
    case UDID = "--udid"
    case Name = "--name"
    case DeviceName = "--device-name"
    case OSVersion = "--os"
    case State = "--state"
    case ProcessIdentifier = "--pid"
  }

  case HumanReadable([Keywords])
  case JSON(Bool)
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
  case (.JSON(let leftPretty), .JSON(let rightPretty)):
    return leftPretty == rightPretty
  case (.HumanReadable(let leftKeywords), .HumanReadable(let rightKeywords)):
    return leftKeywords == rightKeywords
  default:
    return false
  }
}
