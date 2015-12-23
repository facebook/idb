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
 Defines a single transaction with FBSimulatorControl
*/
public struct Command {
  let configuration: Configuration
  let subcommand: Action
}

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
  case And([Query])
}

/**
 An Action that can be performed provided a FBSimulatorControl instance.
*/
public indirect enum Action {
  case Interact(Int?)
  case List(Query, Format)
  case Boot(Query)
  case Shutdown(Query)
  case Diagnose(Query)
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
    var subqueries: [Query] = []
    for query in queries {
      switch query {
      case .UDID(let udid): udids.unionInPlace(udid)
      case .State(let state): states.unionInPlace(state)
      case .Configured(let configuration): configurations.unionInPlace(configuration)
      case .And(let subquery): subqueries.appendContentsOf(subquery)
      }
    }

    if udids.count > 0 {
      let query = Query.UDID(udids)
      if states.count == 0 && configurations.count == 0 {
        return query
      }
      subqueries.append(query)
    }
    if states.count > 0 {
      let query = Query.State(states)
      if udids.count == 0 && configurations.count == 0 {
        return query
      }
      subqueries.append(query)
    }
    if configurations.count > 0 {
      let query = Query.Configured(configurations)
      if udids.count == 0 && states.count == 0 {
        return query
      }
      subqueries.append(query)
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

extension Query : Equatable { }
public func == (leftQuery: Query, rightQuery: Query) -> Bool {
  switch (leftQuery, rightQuery) {
  case (let .UDID(left), let .UDID(right)): return left == right
  case (let .State(left), let .State(right)): return left == right
  case (let .Configured(left), let .Configured(right)): return left == right
  case (let .And(left), let .And(right)): return left == right
  default: return false
  }
}

extension Format : Equatable { }
public func == (lhs: Format, rhs: Format) -> Bool {
  switch (lhs, rhs) {
  case (.UDID, .UDID): return true
  case (.OSVersion, .OSVersion): return true
  case (.DeviceName, .DeviceName): return true
  case (.Name, .Name): return true
  case (let .Compound(leftComp), let .Compound(rightComp)): return leftComp == rightComp
  default: return false
  }
}

extension Format : Hashable {
  public var hashValue: Int {
    get {
      switch self {
      case .UDID:
        return "udid".hashValue
      case .OSVersion:
        return "osversion".hashValue
      case .DeviceName:
        return "devicename".hashValue
      case .Name:
        return "name".hashValue
      case .Compound(let format):
        return format.reduce("compound".hashValue) { previous, next in
          return previous ^ next.hashValue
        }
      }
    }
  }
}
