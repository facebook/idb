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
  let controlConfiguration: FBSimulatorControlConfiguration
  let debugLogging: Bool
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
  case Compound([Format])
}

/**
 Defines the components of Query for Simulators.
 Each of the fundemental cases takes a collection of values to allow for a union for each case.
 Intersection is achieved with the .And enumeration.
*/
public indirect enum Query {
  case UDID(Set<String>)
  case State(Set<FBSimulatorState>)
  case Configured(Set<FBSimulatorConfiguration>)
  case And(Set<Query>)
}

/**
 An Interaction represents a Single, synchronous interaction with a Simulator.
 */
public enum Interaction {
  case List
  case Boot
  case Shutdown
  case Diagnose
  case Install(FBSimulatorApplication)
  case Launch(FBProcessLaunchConfiguration)
}

/**
 An Action represents an Interaction that is performed on a particular Query of Simulators.
*/
public struct Action {
  let interaction: Interaction
  let query: Query
  let format: Format
}

/**
 The entry point for all commands.
 */
public enum Command {
  case Perform(Configuration, [Action])
  case Interact(Configuration, Int?)
  case Help(Interaction?)
}

public extension Query {
  static func flatten(queries: [Query]) -> Query {
    if (queries.count == 1) {
      return queries.first!
    }

    var udids: Set<String> = []
    var states: Set<FBSimulatorState> = []
    var configurations: Set<FBSimulatorConfiguration> = []
    var subqueries: Set<Query> = []
    for query in queries {
      switch query {
      case .UDID(let udid): udids.unionInPlace(udid)
      case .State(let state): states.unionInPlace(state)
      case .Configured(let configuration): configurations.unionInPlace(configuration)
      case .And(let subquery): subqueries.unionInPlace(subquery)
      }
    }

    if udids.count > 0 {
      let query = Query.UDID(udids)
      if states.count == 0 && configurations.count == 0 {
        return query
      }
      subqueries.insert(query)
    }
    if states.count > 0 {
      let query = Query.State(states)
      if udids.count == 0 && configurations.count == 0 {
        return query
      }
      subqueries.insert(query)
    }
    if configurations.count > 0 {
      let query = Query.Configured(configurations)
      if udids.count == 0 && states.count == 0 {
        return query
      }
      subqueries.insert(query)
    }

    return .And(subqueries)
  }
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
  return left.debugLogging == right.debugLogging && left.controlConfiguration == right.controlConfiguration
}

extension Command : Equatable {}
public func == (left: Command, right: Command) -> Bool {
  switch (left, right) {
  case (.Perform(let leftConfiguration, let lefts), .Perform(let rightConfiguration, let rights)):
    return leftConfiguration == rightConfiguration && lefts == rights
  case (.Interact(let leftConfiguration, let leftPort), .Interact(let rightConfiguration, let rightPort)):
    return leftConfiguration == rightConfiguration && leftPort == rightPort
  case (.Help(let left), .Help(let right)):
    return left == right
  default:
    return false
  }
}

extension Action : Equatable { }
public func == (left: Action, right: Action) -> Bool {
  return left.format == right.format && left.query == right.query && left.interaction == right.interaction
}

extension Interaction : Equatable { }
public func == (left: Interaction, right: Interaction) -> Bool {
  switch (left, right) {
  case (.List, .List):
    return true
  case (.Boot, .Boot):
    return true
  case (.Shutdown, .Shutdown):
    return true
  case (.Diagnose, .Diagnose):
    return true
  case (.Install(let leftApp), .Install(let rightApp)):
    return leftApp == rightApp
  case (.Launch(let leftLaunch), .Launch(let rightLaunch)):
    return leftLaunch == rightLaunch
  default:
    return false
  }
}

extension Query : Equatable { }
public func == (left: Query, right: Query) -> Bool {
  switch (left, right) {
  case (.UDID(let left), .UDID(let right)): return left == right
  case (.State(let left), .State(let right)): return left == right
  case (.Configured(let left), .Configured(let right)): return left == right
  case (.And(let left), .And(let right)): return left == right
  default: return false
  }
}

extension Query : Hashable {
  public var hashValue: Int {
    get {
      switch self {
      case .UDID(let udids):
        return 1 ^ udids.hashValue
      case .Configured(let configurations):
        return 2 ^ configurations.hashValue
      case .State(let states):
        return 4 ^ states.hashValue
      case .And(let subqueries):
        return subqueries.hashValue
      }
    }
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
      case .Compound(let format):
        return format.reduce("compound".hashValue) { previous, next in
          return previous ^ next.hashValue
        }
      }
    }
  }
}
