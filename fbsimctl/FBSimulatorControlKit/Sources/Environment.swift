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

public extension CLI {
  func appendEnvironment(environment: [String : String]) -> CLI {
    switch self {
    case .Run(let command):
      return .Run(command.appendEnvironment(environment))
    default:
      return self
    }
  }
}

public extension Command {
  func appendEnvironment(environment: [String : String]) -> Command {
    return Command(
      configuration: self.configuration,
      actions: self.actions.map { $0.appendEnvironment(environment) },
      query: self.query,
      format: self.format
    )
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
    case .LaunchXCTest(let configuration, let bundle, let timeout):
      return .LaunchXCTest(
        configuration.withEnvironmentAdditions(
          Action.subprocessEnvironment(environment)
        ),
        bundle,
        timeout
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
