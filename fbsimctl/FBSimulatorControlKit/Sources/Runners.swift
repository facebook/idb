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
import FBControlCore

/**
 Some work, yielding a result.
 */
protocol Runner {
  func run() -> CommandResult
}

/**
 Joins multiple Runners together.
 */
struct SequenceRunner : Runner {
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
struct CommandResultRunner : Runner {
  let result: CommandResult

  func run() -> CommandResult {
    return self.result
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
struct RelayRunner : Runner {
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
