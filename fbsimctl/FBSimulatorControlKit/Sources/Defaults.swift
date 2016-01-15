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
        controlConfiguration: self.defaultControlConfiguration,
        options: Configuration.Options()
      )
    }
  }

  public static var defaultControlConfiguration: FBSimulatorControlConfiguration {
    get {
      return FBSimulatorControlConfiguration(
        deviceSetPath: nil,
        options: FBSimulatorManagementOptions()
      )
    }
  }
}

extension Configuration {
  func updateIfNonDefault(configuration: Configuration) -> Configuration {
    if self == Configuration.defaultValue {
      return configuration
    }
    return self
  }
}

let DefaultsRCFile = NSURL(fileURLWithPath: NSHomeDirectory()).URLByAppendingPathComponent(".fbsimctlrc", isDirectory: false)

public struct Defaults {
  let logWriter: Writer
  let format: Format
  let configuration: Configuration
  var query: Query?

  static func create(configuration: Configuration, logWriter: Writer) throws -> Defaults {
    do {
      var configuration: Configuration = configuration
      var format: Format? = nil

      if let rcContents = try? String(contentsOfURL: DefaultsRCFile) {
        let rcTokens = Arguments.fromString(rcContents)
        let (_, result) = try self.rcFileParser.parse(rcTokens)
        if let rcConfiguration = result.0 {
          configuration = configuration.updateIfNonDefault(rcConfiguration)
        }
        if let rcFormat = result.1 {
          format = rcFormat
        }
      }

      return Defaults(
        logWriter: logWriter,
        format: format ?? Format.defaultValue,
        configuration: configuration,
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

