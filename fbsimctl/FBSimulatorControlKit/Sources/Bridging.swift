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

extension FBSimulatorState {
  public var description: String {
    get {
      return FBSimulator.stateStringFromSimulatorState(self)
    }
  }
}

public typealias ControlCoreValue = protocol<FBJSONSerializable, CustomStringConvertible>

@objc public class ControlCoreLoggerBridge : NSObject {
  let reporter: EventReporter

  init(reporter: EventReporter) {
    self.reporter = reporter
  }

  @objc public func log(level: Int32, string: String) {
    let subject = LogSubject(logString: string, level: level)
    self.reporter.report(subject)
  }
}

extension String : CustomStringConvertible {
  public var description: String { get {
    return self
  }}
}

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

extension FBSimulatorQuery {
  public static func simulatorStates(states: [FBSimulatorState]) -> FBSimulatorQuery {
    return self.allSimulators().simulatorStates(states)
  }

  public func simulatorStates(states: [FBSimulatorState]) -> FBSimulatorQuery {
    return self.states(states.map{ NSNumber(integer: $0.rawValue) })
  }

  public static func ofCount(count: Int) -> FBSimulatorQuery {
    return self.allSimulators().ofCount(count)
  }

  public func ofCount(count: Int) -> FBSimulatorQuery {
    return self.range(NSRange(location: 0, length: count))
  }

  static func perform(set: FBSimulatorSet, query: FBSimulatorQuery?, defaults: Defaults, action: Action) throws -> [FBSimulator] {
    guard let query = query ?? defaults.queryForAction(action) else {
      throw QueryError.NoQueryProvided
    }
    if set.allSimulators.count == 0 {
      throw QueryError.PoolIsEmpty
    }
    let matching = query.perform(set)
    if matching.count == 0 {
      throw QueryError.NoMatches
    }
    defaults.updateLastQuery(query)
    return matching
  }
}

extension FBSimulatorQuery : Accumilator {
  public func append(other: FBSimulatorQuery) -> Self {
    let deviceSet = other.devices as NSSet
    let deviceArray = Array(deviceSet) as! [FBSimulatorConfiguration_Device]
    let osVersionsSet = other.osVersions as NSSet
    let osVersionsArray = Array(osVersionsSet) as! [FBSimulatorConfiguration_OS]

    return self
      .udids(Array(other.udids))
      .states(Array(other.states))
      .devices(deviceArray)
      .osVersions(osVersionsArray)
      .range(other.range)
  }
}
