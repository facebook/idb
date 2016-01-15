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

let DefaultsRCFile = NSURL(fileURLWithPath: NSHomeDirectory()).URLByAppendingPathComponent(".fbsimctlrc", isDirectory: false)

public enum DefaultsError : ErrorType, CustomStringConvertible {
  case UnreadableRCFile(String)

  public var description: String {
    get {
      switch self {
      case .UnreadableRCFile(let underlyingError):
        return "Unreadable RC File " + underlyingError
      }
    }
  }
}

public protocol Defaultable {
  static var defaultValue: Self { get }
}

extension Format : Defaultable {
  public static var defaultValue: Format {
    get {
      return .Compound([ .UDID, .Name])
    }
  }
}

extension Configuration : Defaultable {
  public static var defaultValue: Configuration {
    get {
      return Configuration(
        controlConfiguration: FBSimulatorControlConfiguration(
          deviceSetPath: nil,
          options: FBSimulatorManagementOptions()
        ),
        options: Configuration.Options()
      )
    }
  }
}

public struct Defaults {
  let format: Format
  let configuration: Configuration
  let query: Query?

  static func from(setPath: String?) throws -> Defaults {
    do {
      var configuration: Configuration? = nil
      var format: Format? = nil
      if let rcContents = try? String(contentsOfURL: DefaultsRCFile) {
        let rcTokens = Arguments.fromString(rcContents)
        (_, (configuration, format)) = try self.rcFileParser.parse(rcTokens)
      }

      return Defaults(
        format: format ?? Format.defaultValue,
        configuration: configuration ?? Configuration.defaultValue,
        query: nil
      )
    } catch let error as ParseError {
      throw DefaultsError.UnreadableRCFile(error.description)
    }
  }

  static var rcFileParser: Parser<(Configuration?, Format?)> {
    get {
      return Parser.ofTwoSequenced(
        Configuration.parser().optional(),
        Format.parser().optional()
      )
    }
  }
}

