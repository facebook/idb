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
  let subcommand: Subcommand
}

/**
  Describes the Configuration for the running of a Command
*/
public final class Configuration : FBSimulatorControlConfiguration {
  public static func defaultConfiguration() -> Configuration {
    return Configuration(
      simulatorApplication: try! FBSimulatorApplication(error: ()),
      deviceSetPath: nil,
      options: FBSimulatorManagementOptions()
    )
  }
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
 The Base of all fbsimctl commands
*/
public indirect enum Subcommand {
  case Interact(Int?)
  case List(Query, Format)
  case Boot(Query)
  case Shutdown(Query)
  case Diagnose(Query)
  case Help(Subcommand?)
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
      subqueries.append(.UDID(udids))
    }
    if states.count > 0 {
      subqueries.append(.State(states))
    }
    if configurations.count > 0 {
      subqueries.append(.Configured(configurations))
    }

    return .And(subqueries)
  }
}
