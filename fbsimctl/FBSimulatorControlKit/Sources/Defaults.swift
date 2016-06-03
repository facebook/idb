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
private let defaultFormat: Format = [ .UDID, .Name, .OSVersion, .State]

extension Configuration : Defaultable {
  public static var defaultValue: Configuration { get {
    return Configuration()
  }}
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

/**
 Provides Default Values, with overrides from a .rc file
 as well as updates to defaults to avoid repetitious commands.
*/
public class Defaults {
  let logWriter: Writer
  let format: Format
  let configuration: Configuration
  private var query: FBiOSTargetQuery?

  init(logWriter: Writer, format: Format, configuration: Configuration) {
    self.logWriter = logWriter
    self.format = format
    self.configuration = configuration
  }

  func updateLastQuery(query: FBiOSTargetQuery) {
    // TODO: Create the CLI equivalent of the configuration and save.
    let _ = Defaults.queryHistoryLocation(configuration)
    self.query = query
  }

  func queryForAction(action: Action) -> FBiOSTargetQuery? {
    // Always use the last query, if present
    if let query = self.query {
      return query
    }
    // Use reasonable defaults for each action.
    // Depending on what state the simulator is expected to be in.
    // Descructive of machine-killing actions shouldn't have defaults.
    switch action {
      case .Boot:
        fallthrough
      case .Delete:
        return nil
      case .List:
        fallthrough
      case .Search:
        fallthrough
      case .Diagnose:
        return FBiOSTargetQuery.allSimulators()
      case .Approve:
        return FBiOSTargetQuery.simulatorStates([.Shutdown])
      default:
        return FBiOSTargetQuery.simulatorStates([.Booted])
    }
  }

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
        format: format ?? defaultFormat,
        configuration: configuration
      )
    } catch let error as ParseError {
      throw DefaultsError.UnreadableRCFile(error.description)
    }
  }

  private static var rcFileParser: Parser<(Configuration?, Format?)> { get {
    return Parser
      .ofTwoSequenced(
        Configuration.parser.optional(),
        Format.parser.optional()
      )
  }}

  private static func queryHistoryLocation(configuration: Configuration) -> NSURL {
    let setPath = configuration.deviceSetPath ?? FBSimulatorControlConfiguration.defaultDeviceSetPath()
    return NSURL(fileURLWithPath: setPath).URLByAppendingPathComponent(".fbsimctl_last_query")
  }
}
