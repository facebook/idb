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
 Base Options that are also used in Help.
 */
public struct OutputOptions : OptionSet {
  public let rawValue : Int
  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  public static let DebugLogging = OutputOptions(rawValue: 1 << 0)
  public static let JSON = OutputOptions(rawValue: 1 << 1)
  public static let Pretty = OutputOptions(rawValue: 1 << 2)
}

/**
 Some Actions performed on some targets.
 */
public struct Help {
  let outputOptions: OutputOptions
  let error: (Error & CustomStringConvertible)?
  let command: Command?
}
extension Help : Equatable {}
public func == (left: Help, right: Help) -> Bool {
  return left.outputOptions == right.outputOptions && left.command == right.command
}

public enum CLI {
  case print(Action)
  case run(Command)
  case show(Help)
}

extension CLI : Equatable {}
public func == (left: CLI, right: CLI) -> Bool {
  switch (left, right) {
    case (.show(let leftHelp), .show(let rightHelp)):
      return leftHelp == rightHelp
    case (.run(let leftCommand), .run(let rightCommand)):
      return leftCommand == rightCommand
    case (.print(let leftAction), .print(let rightAction)):
      return leftAction == rightAction
    default:
      return false
  }
}

