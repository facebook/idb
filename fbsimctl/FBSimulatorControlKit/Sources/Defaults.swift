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

public enum DefaultsError : Error, CustomStringConvertible {
  case unreadableRCFile(String)

  public var description: String { get {
    switch self {
    case .unreadableRCFile(let underlyingError):
      return "Unreadable RC File " + underlyingError
    }
  }}
}

public protocol Defaultable {
  static var defaultValue: Self { get }
}

extension Configuration : Defaultable {
  public static var defaultValue: Configuration { get {
    return Configuration()
  }}
}

extension Configuration {
  func updateIfNonDefault(_ configuration: Configuration) -> Configuration {
    if self == Configuration.defaultValue {
      return configuration
    }
    return self
  }
}

let DefaultsRCFile: URL = URL.urlRelativeTo(NSHomeDirectory(), component: ".fbsimctlrc", isDirectory: false)

/**
 Provides Default Values, with overrides from a .rc file
 as well as updates to defaults to avoid repetitious commands.
*/
open class Defaults {
  let logWriter: Writer
  let format: FBiOSTargetFormat
  let configuration: Configuration
  fileprivate var query: FBiOSTargetQuery?

  init(logWriter: Writer, format: FBiOSTargetFormat, configuration: Configuration) {
    self.logWriter = logWriter
    self.format = format
    self.configuration = configuration
  }

  func updateLastQuery(_ query: FBiOSTargetQuery) {
    // TODO: Create the CLI equivalent of the configuration and save.
    let _ = Defaults.queryHistoryLocation(configuration)
    self.query = query
  }

  func queryForAction(_ action: Action) -> FBiOSTargetQuery? {
    // Always use the last query, if present
    if let query = self.query {
      return query
    }
    return action.defaultQuery
  }

  static func create(_ configuration: Configuration, logWriter: Writer) throws -> Defaults {
    do {
      var configuration: Configuration = configuration
      var format: FBiOSTargetFormat? = nil

      if let rcContents = try?  String(contentsOf: DefaultsRCFile) {
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
        format: format ?? FBiOSTargetFormat.default(),
        configuration: configuration
      )
    } catch let error as ParseError {
      throw DefaultsError.unreadableRCFile(error.description)
    }
  }

  fileprivate static var rcFileParser: Parser<(Configuration?, FBiOSTargetFormat?)> { get {
    return Parser
      .ofTwoSequenced(
        Configuration.parser.optional(),
        FBiOSTargetFormatParsers.parser.optional()
      )
  }}

  fileprivate static func queryHistoryLocation(_ configuration: Configuration) -> URL {
    let setPath = configuration.deviceSetPath ?? FBSimulatorControlConfiguration.defaultDeviceSetPath()
    return URL.urlRelativeTo(setPath, component: ".fbsimctl_last_query", isDirectory: false)
  }
}

extension Action {
  var defaultQuery: FBiOSTargetQuery? { get {
    // Use reasonable defaults for each action.
    // Depending on what state the simulator is expected to be in.
    // Descructive of machine-killing actions shouldn't have defaults.
    switch self {
      case .delete:
        return nil
      case .core(let action):
        return type(of: action).actionType.defaultQuery
      case .list:
        fallthrough
      case .listen:
        fallthrough
      case .search:
        fallthrough
      case .diagnose:
        return FBiOSTargetQuery.allTargets()
      case .approve:
        return FBiOSTargetQuery.state(.shutdown)
      default:
        return FBiOSTargetQuery.state(.booted)
    }
  }}
}

extension FBiOSTargetActionType {
  var defaultQuery: FBiOSTargetQuery? { get {
    switch self {
      case FBiOSTargetActionType.boot:
        return nil
      default:
        return FBiOSTargetQuery.state(.booted)
    }
  }}
}
