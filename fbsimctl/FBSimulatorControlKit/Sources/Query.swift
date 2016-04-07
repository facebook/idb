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
    let array: NSArray = set.allSimulators
    let matching = array.filteredArrayUsingPredicate(query.get(set)) as! [FBSimulator]
    if matching.count == 0 {
      throw QueryError.NoMatches
    }
    defaults.updateLastQuery(query)
    return matching
  }

  func get(set: FBSimulatorSet) -> NSPredicate {
    switch (self) {
    case .UDID(let udids):
      return FBSimulatorPredicates.udids(Array(udids))
    case .State(let states):
      return NSCompoundPredicate(
        orPredicateWithSubpredicates: states.map(FBSimulatorPredicates.state)
      )
    case .Configured(let configurations):
      return NSCompoundPredicate(
        orPredicateWithSubpredicates: configurations.map(FBSimulatorPredicates.configuration)
      )
    case .And(let subqueries):
      return NSCompoundPredicate(
        andPredicateWithSubpredicates: subqueries.map { $0.get(set) }
      )
    }
  }
}

/**
 Extracts values for each of the cases in the enumeration,
 performing a union along each of these cases.
*/
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
