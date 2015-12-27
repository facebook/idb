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
public final class Configuration : FBSimulatorControlConfiguration {
}

/**
 Defines a Format for displaying Simulator Information
*/
public indirect enum Format {
  case UDID
  case Name
  case DeviceName
  case OSVersion
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
 An Action that can be performed provided a FBSimulatorControl instance.
*/
public indirect enum Action {
  case List(Query, Format)
  case Boot(Query)
  case Shutdown(Query)
  case Diagnose(Query)
  case Help(Action?)
}

/**
 The entry point for all commands.
 */
public enum Command {
  case Single(Configuration, Action)
  case Interact(Configuration, Int?)
  case Help(Action?)
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

extension Command : Equatable {}
public func == (left: Command, right: Command) -> Bool {
  switch (left, right) {
  case (.Single(let leftConfiguration, let leftAction), .Single(let rightConfiguration, let rightAction)):
    return leftConfiguration == rightConfiguration && leftAction == rightAction
  case (.Interact(let leftConfiguration, let leftPort), .Interact(let rightConfiguration, let rightPort)):
    return leftConfiguration == rightConfiguration &&  leftPort == rightPort
  case (.Help(let leftAction), .Help(let rightAction)):
    return leftAction == rightAction
  default:
    return false
  }
}

extension Action : Equatable { }
public func == (leftAction: Action, rightAction: Action) -> Bool {
  switch (leftAction, rightAction) {
  case (.List(let leftQuery, let leftFormat), .List(let rightQuery, let rightFormat)):
    return leftQuery == rightQuery && leftFormat == rightFormat
  case (.Boot(let leftQuery), .Boot(let rightQuery)):
    return leftQuery == rightQuery
  case (.Shutdown(let leftQuery), .Shutdown(let rightQuery)):
    return leftQuery == rightQuery
  case (.Diagnose(let leftQuery), .Diagnose(let rightQuery)):
    return leftQuery == rightQuery
  case (.Help(let leftHelp), .Help(let rightHelp)):
    return leftHelp == rightHelp
  default:
    return false
  }
}

extension Query : Equatable { }
public func == (leftQuery: Query, rightQuery: Query) -> Bool {
  switch (leftQuery, rightQuery) {
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
public func == (lhs: Format, rhs: Format) -> Bool {
  switch (lhs, rhs) {
  case (.UDID, .UDID): return true
  case (.OSVersion, .OSVersion): return true
  case (.DeviceName, .DeviceName): return true
  case (.Name, .Name): return true
  case (.Compound(let leftComp), .Compound(let rightComp)): return leftComp == rightComp
  default: return false
  }
}

extension Format : Hashable {
  public var hashValue: Int {
    get {
      switch self {
      case .UDID:
        return 1
      case .OSVersion:
        return 2
      case .DeviceName:
        return 3
      case .Name:
        return 4
      case .Compound(let format):
        return format.reduce("compound".hashValue) { previous, next in
          return previous ^ next.hashValue
        }
      }
    }
  }
}
