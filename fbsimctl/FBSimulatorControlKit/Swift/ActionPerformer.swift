/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/**
 Defines the Output of running a Command.
 */
public struct CommandResult {
  let outcome: CommandOutcome
  let continuations: [FBiOSTargetContinuation]

  static func success(_ subject: EventReporterSubject?) -> CommandResult {
    return CommandResult(outcome: .success(subject), continuations: [])
  }

  static func failure(_ message: String) -> CommandResult {
    return CommandResult(outcome: .failure(message), continuations: [])
  }

  func append(_ second: CommandResult) -> CommandResult {
    return CommandResult(
      outcome: outcome.append(second.outcome),
      continuations: continuations + second.continuations
    )
  }
}

@objc class CommandResultBox: NSObject {
  let value: CommandResult

  init(value: CommandResult) {
    self.value = value
  }
}

/**
 Runs an Action, yielding a result
 */
protocol ActionPerformer {
  var configuration: Configuration { get }
  var query: FBiOSTargetQuery { get }

  func runnerContext(_ reporter: EventReporter) -> iOSRunnerContext<()>
  func future(reporter: EventReporter, action: Action, queryOverride: FBiOSTargetQuery?) -> FBFuture<CommandResultBox>
}

/**
 Defines the Outcome of runnic a Command.
 */
public enum CommandOutcome: CustomStringConvertible, CustomDebugStringConvertible {
  case success(EventReporterSubject?)
  case failure(String)

  func append(_ second: CommandOutcome) -> CommandOutcome {
    switch (self, second) {
    case let (.success(.some(leftSubject)), .success(.some(rightSubject))):
      return .success(leftSubject.append(rightSubject))
    case (let .success(.some(leftSubject)), .success(.none)):
      return .success(leftSubject)
    case let (.success(.none), .success(.some(rightSubject))):
      return .success(rightSubject)
    case (.success, .success):
      return .success(nil)
    case let (.success, .failure(secondString)):
      return .failure(secondString)
    case (let .failure(firstString), .success):
      return .failure(firstString)
    case let (.failure(firstString), .failure(secondString)):
      return .failure("\(firstString)\n\(secondString)")
    }
  }

  public var description: String {
    switch self {
    case .success: return "Success"
    case let .failure(string): return "Failure '\(string)'"
    }
  }

  public var debugDescription: String {
    return description
  }
}
