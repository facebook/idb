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
public struct OutputOptions : OptionSetType {
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
  let userInitiated: Bool
  let command: Command?
}

public enum CLI {
  case Show(Help)
  case Run(Command)
}

public extension CLI {
  public static func fromArguments(arguments: [String], environment: [String : String]) -> CLI {
    let help = Help(outputOptions: OutputOptions(), userInitiated: false, command: nil)

    do {
      let (_, cli) = try CLI.parser.parse(arguments)
      return cli.appendEnvironment(environment)
    } catch let error as ParseError {
      print("Failed to Parse Command \(error)")
      return CLI.Show(help)
    } catch let error as NSError {
      print("Failed to Parse Command \(error)")
      return CLI.Show(help)
    }
  }
}
