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
  func perform(command: Command, reporter: EventReporter) -> CommandResult
}

/**
 Forwards to a CommandPerformer based on Constructor Arguments
 */
struct ActionPerformer {
  let commandPerformer: CommandPerformer
  let configuration: Configuration
  let query: FBiOSTargetQuery
  let format: Format?

  func perform(reporter: EventReporter, action: Action, queryOverride: FBiOSTargetQuery? = nil, formatOverride: Format? = nil) -> CommandResult {
    let command = Command.Perform(self.configuration, [action], queryOverride ?? self.query, formatOverride ?? self.format)
    return self.commandPerformer.perform(command, reporter: reporter)
  }
}

extension CommandPerformer {
  func perform(input: String, reporter: EventReporter) -> CommandResult {
    do {
      let arguments = Arguments.fromString(input)
      let (_, command) = try Command.parser.parse(arguments)
      return self.perform(command, reporter: reporter)
    } catch let error as ParseError {
      return .Failure("Error: \(error.description)")
    } catch let error as NSError {
      return .Failure(error.description)
    }
  }
}

/**
 Enum for defining the result of a translation.
 */
public enum CommandResult {
  case Success
  case Failure(String)

  func append(second: CommandResult) -> CommandResult {
    switch (self, second) {
    case (.Success, .Success):
      return .Success
    case (.Success, .Failure(let secondString)):
      return .Failure(secondString)
    case (.Failure(let firstString), .Success):
      return .Failure(firstString)
    case (.Failure(let firstString), .Failure(let secondString)):
      return .Failure("\(firstString)\n\(secondString)")
    }
  }
}

extension CommandResult : CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    get {
      switch self {
      case .Success: return "Success"
      case .Failure(let string): return "Failure '\(string)'"
      }
    }
  }

  public var debugDescription: String {
    get {
      return self.description
    }
  }
}
