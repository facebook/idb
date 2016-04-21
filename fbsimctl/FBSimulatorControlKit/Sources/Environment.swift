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

let EnvironmentPrefix = "FBSIMCTL_CHILD_"

public extension Command {
  func appendEnvironment(environment: [String : String]) -> Command {
    switch self {
    case .Perform(let configuration, let actions, let query, let format):
      return .Perform(
        configuration,
        actions.map { $0.appendEnvironment(environment) },
        query,
        format
      )
    default:
      return self
    }
  }
}

public extension Action {
  func appendEnvironment(environment: [String : String]) -> Action {
    switch self {
    case .LaunchApp(let configuration):
      return .LaunchApp(
        configuration.withEnvironmentAdditions(
          Action.subprocessEnvironment(environment)
        )
      )
    case .LaunchAgent(let configuration):
      return .LaunchAgent(
        configuration.withEnvironmentAdditions(
          Action.subprocessEnvironment(environment)
        )
      )
    default:
      return self
    }
  }

  private static func subprocessEnvironment(environment: [String : String]) -> [String : String] {
    var additions: [String : String] = [:]
    for (key, value) in environment {
      if !key.hasPrefix(EnvironmentPrefix) {
        continue
      }
      additions[key.stringByReplacingOccurrencesOfString(EnvironmentPrefix, withString: "")] = value
    }
    return additions
  }
}
