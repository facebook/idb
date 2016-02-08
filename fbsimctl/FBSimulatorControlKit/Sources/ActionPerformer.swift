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
 A Protocol for performing an Action producing an ActionResult.
 */
protocol ActionPerformer {
  func perform(action: Action, reporter: EventReporter) -> ActionResult
}

extension ActionPerformer {
  func perform(input: String, reporter: EventReporter) -> ActionResult {
    do {
      let arguments = Arguments.fromString(input)
      let (_, action) = try Action.parser().parse(arguments)
      return self.perform(action, reporter: reporter)
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
public enum ActionResult {
  case Success
  case Failure(String)

  func append(second: ActionResult) -> ActionResult {
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

extension ActionResult : CustomStringConvertible, CustomDebugStringConvertible {
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
