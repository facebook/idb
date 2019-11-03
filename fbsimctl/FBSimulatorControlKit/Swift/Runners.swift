/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBSimulatorControl
import Foundation

/**
 Some work, yielding a result.
 */
protocol Runner {
  func run() -> CommandResult
}

/**
 Joins multiple Runners together.
 */
struct SequenceRunner: Runner {
  let runners: [Runner]

  func run() -> CommandResult {
    var output = CommandResult.success(nil)
    for runner in runners {
      output = output.append(runner.run())
      switch output.outcome {
      case .failure: return output
      default: continue
      }
    }
    return output
  }
}

/**
 Wraps a CommandResult in a runner
 */
struct CommandResultRunner: Runner {
  let result: CommandResult

  func run() -> CommandResult {
    return result
  }
}

extension CommandResult {
  func asRunner() -> Runner {
    return CommandResultRunner(result: self)
  }
}

/**
 Wraps a Synchronous Relay in a Runner.
 */
struct RelayRunner: Runner {
  let relay: SynchronousRelay

  func run() -> CommandResult {
    do {
      try relay.start()
      try relay.stop()
      return .success(nil)
    } catch let error as CustomStringConvertible {
      return .failure(error.description)
    } catch {
      return .failure("An unknown error occurred running the server")
    }
  }
}
