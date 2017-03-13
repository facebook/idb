/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

/**
 A Protocol for performing an Command producing an CommandResult.
 */
protocol CommandPerformer {
  func runnerContext(_ reporter: EventReporter) -> iOSRunnerContext<()>
  func perform(_ command: Command, reporter: EventReporter) -> CommandResult
}

/**
 Forwards to a CommandPerformer based on Constructor Arguments
 */
struct ActionPerformer {
  let commandPerformer: CommandPerformer
  let configuration: Configuration
  let query: FBiOSTargetQuery
  let format: FBiOSTargetFormat?

  func perform(_ reporter: EventReporter, action: Action, queryOverride: FBiOSTargetQuery? = nil, formatOverride: FBiOSTargetFormat? = nil) -> CommandResult {
    let command = Command(
      configuration: self.configuration,
      actions: [action],
      query: queryOverride ?? self.query,
      format: formatOverride ?? self.format
    )
    return self.commandPerformer.perform(command, reporter: reporter)
  }
}

extension CommandPerformer {
  func perform(_ input: String, reporter: EventReporter) -> CommandResult {
    do {
      let arguments = Arguments.fromString(input)
      let (_, command) = try Command.parser.parse(arguments)
      return self.perform(command, reporter: reporter)
    } catch let error as ParseError {
      return .failure("Error: \(error.description)")
    } catch let error as NSError {
      return .failure(error.description)
    }
  }
}

/**
 Defines the Output of running a Command.
 */
public struct CommandResult {
  let outcome: CommandOutcome
  let handles: [FBTerminationHandle]

  static func success(_ subject: EventReporterSubject?) -> CommandResult {
    return CommandResult(outcome: .success(subject), handles: [])
  }

  static func failure(_ message: String) -> CommandResult {
    return CommandResult(outcome: .failure(message), handles: [])
  }

  func append(_ second: CommandResult) -> CommandResult {
    return CommandResult(
      outcome: self.outcome.append(second.outcome),
      handles: self.handles + second.handles
    )
  }
}

/**
 Defines the Outcome of runnic a Command.
 */
public enum CommandOutcome : CustomStringConvertible, CustomDebugStringConvertible {
  case success(EventReporterSubject?)
  case failure(String)

  func append(_ second: CommandOutcome) -> CommandOutcome {
    switch (self, second) {
    case (.success(.some(let leftSubject)), .success(.some(let rightSubject))):
      return .success(leftSubject.append(rightSubject))
    case (.success(.some(let leftSubject)), .success(.none)):
      return .success(leftSubject)
    case (.success(.none), .success(.some(let rightSubject))):
      return .success(rightSubject)
    case (.success, .success):
      return .success(nil)
    case (.success, .failure(let secondString)):
      return .failure(secondString)
    case (.failure(let firstString), .success):
      return .failure(firstString)
    case (.failure(let firstString), .failure(let secondString)):
      return .failure("\(firstString)\n\(secondString)")
    }
  }

  public var description: String { get {
    switch self {
    case .success: return "Success"
    case .failure(let string): return "Failure '\(string)'"
    }
  }}

  public var debugDescription: String { get {
    return self.description
  }}
}
