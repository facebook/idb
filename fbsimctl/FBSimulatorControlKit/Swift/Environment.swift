/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
    case let .run(command):
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

extension EnvironmentAdditive {}

extension FBSimulatorBootConfiguration: EnvironmentAdditive {
  func withEnvironmentAdditions(_ environmentAdditions: [String: String]) -> Self {
    return withBootEnvironment(environmentAdditions)
  }
}

public extension Action {
  func appendEnvironment(_ environment: [String: String]) -> Action {
    switch self {
    case var .coreFuture(action):
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
