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

public enum QueryError : CustomStringConvertible, ErrorType {
  case NoMatches
  case NoQueryProvided
  case PoolIsEmpty

  public var description: String {
    get {
      switch self {
      case .NoMatches: return "No Matching Simulators"
      case .NoQueryProvided: return "No Query Provided"
      case .PoolIsEmpty: return "Device Set is Empty"
      }
    }
  }
}

/**
 Defines the components of Query for Simulators.
 */
public struct Query {
  let udids: Set<String>
  let states: Set<FBSimulatorState>
  let devices: Set<String>
  let osVersions: Set<String>
  let count: Int?
}

extension Query : Accumilator {
  public init() {
    self.udids = Set()
    self.states = Set()
    self.devices = Set()
    self.osVersions = Set()
    self.count = nil
  }

  public static var identity: Query { get {
    return Query.all
  }}

  public func append(other: Query) -> Query {
    let count = other.count ?? self.count ?? nil
    return Query(
      udids: self.udids.union(other.udids),
      states: self.states.union(other.states),
      devices: self.devices.union(other.devices),
      osVersions: self.osVersions.union(other.osVersions),
      count: count
    )
  }

  public static var all: Query { get {
    return Query()
  }}

  public static func ofUDIDs(udids: [String]) -> Query {
    let query = self.all
    return Query(udids: Set(udids), states: query.states, devices: query.devices, osVersions: query.osVersions, count: query.count)
  }

  public static func ofStates(states: [FBSimulatorState]) -> Query {
    let query = self.all
    return Query(udids: query.udids, states: Set(states), devices: query.devices, osVersions: query.osVersions, count: query.count)
  }

  public static func ofDevices(devices: [String]) -> Query {
    let query = self.all
    return Query(udids: query.udids, states: query.states, devices: Set(devices), osVersions: query.osVersions, count: query.count)
  }

  public static func ofOSVersions(osVersions: [String]) -> Query {
    let query = self.all
    return Query(udids: query.udids, states: query.states, devices: query.devices, osVersions: Set(osVersions), count: query.count)
  }

  public static func ofCount(count: Int) -> Query {
    let query = self.all
    return Query(udids: query.udids, states: query.states, devices: query.devices, osVersions: query.osVersions, count: count)
  }
}
extension Query : Equatable { }
public func == (left: Query, right: Query) -> Bool {
  return left.udids == right.udids &&
         left.states == right.states &&
         left.devices == right.devices &&
         left.osVersions == right.osVersions &&
         left.count == right.count
}

/**
 Given a Query and a Pool, obtain a list of the Simulators
*/
extension Query {
  static func perform(set: FBSimulatorSet, query: Query?, defaults: Defaults, action: Action) throws -> [FBSimulator] {
    guard let query = query ?? defaults.queryForAction(action) else {
      throw QueryError.NoQueryProvided
    }
    if set.allSimulators.count == 0 {
      throw QueryError.PoolIsEmpty
    }
    let matching = query.fetch(set)
    if matching.count == 0 {
      throw QueryError.NoMatches
    }
    defaults.updateLastQuery(query)
    return matching
  }

  func fetch(set: FBSimulatorSet) -> [FBSimulator] {
    var predicates: [NSPredicate] = []
    let all: NSArray = set.allSimulators

    if self.udids.count > 0 {
      predicates.append(FBSimulatorPredicates.udids(Array(self.udids)))
    }
    if self.states.count > 0 {
      let states = self.states.map { NSNumber(integer: $0.rawValue) }
      predicates.append(FBSimulatorPredicates.states(states))
    }
    if self.devices.count > 0 {
      predicates.append(FBSimulatorPredicates.devicesNamed(Array(self.devices)))
    }
    if self.osVersions.count > 0 {
      predicates.append(FBSimulatorPredicates.osVersionsNamed(Array(self.osVersions)))
    }
    if predicates.count == 0 {
      return all as! [FBSimulator]
    }
    let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    let simulators = all.filteredArrayUsingPredicate(predicate) as! [FBSimulator]
    guard let count = self.count else {
      return simulators
    }
    return Array(simulators.prefix(count))
  }
}
