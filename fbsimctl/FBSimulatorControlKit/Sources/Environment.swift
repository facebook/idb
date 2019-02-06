/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import FBSimulatorControl
import Foundation

let EnvironmentPrefix = "FBSIMCTL_CHILD_"

private func extractChildProcessEnvironment(_ environment: [String: String]) -> [String: String] {
  var additions: [String: String] = [:]
  for (key, value) in environment {
    if !key.hasPrefix(EnvironmentPrefix) {
      continue
    }
    additions[key.replacingOccurrences(of: EnvironmentPrefix, with: "")] = value
  }
  return additions
}

public extension CLI {
  func appendEnvironment(_ environment: [String: String]) -> CLI {
    switch self {
    case .run(let command):
      return .run(command.appendEnvironment(environment))
    default:
      return self
    }
  }
}

public extension Command {
  func appendEnvironment(_ environment: [String: String]) -> Command {
    return Command(
      configuration: configuration,
      actions: actions.map { $0.appendEnvironment(environment) },
      query: query,
      format: format
    )
  }
}

protocol EnvironmentAdditive {
  func withEnvironmentAdditions(_ environmentAdditions: [String: String]) -> Self
}

extension EnvironmentAdditive {
}

extension FBSimulatorBootConfiguration: EnvironmentAdditive {
  func withEnvironmentAdditions(_ environmentAdditions: [String: String]) -> Self {
    return withBootEnvironment(environmentAdditions)
  }
}

public extension Action {
  func appendEnvironment(_ environment: [String: String]) -> Action {
    switch self {
    case .coreFuture(var action):
      if let additive = action as? EnvironmentAdditive & FBiOSTargetFuture {
        action = additive.withEnvironmentAdditions(
          extractChildProcessEnvironment(environment)
        )
      }
      return .coreFuture(action)
    default:
      return self
    }
  }
}
