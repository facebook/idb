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
    case .Perform(let config, let action):
      return .Perform(config, action.map { $0.appendEnvironment(environment) })
    default:
      return self
    }
  }
}

public extension Action {
  func appendEnvironment(environment: [String : String]) -> Action {
    return Action(
      interaction: self.interaction.appendEnvironment(environment),
      query: self.query,
      format: self.format
    )
  }
}

public extension Interaction {
  func appendEnvironment(environment: [String : String]) -> Interaction {
    switch self {
    case .Launch(let configuration):
      return .Launch(
        configuration.withEnvironmentAdditions(
          Interaction.subprocessEnvironment(environment)
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
