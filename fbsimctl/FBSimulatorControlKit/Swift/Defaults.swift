/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
import Foundation

public enum DefaultsError: Error, CustomStringConvertible {
  case unreadableRCFile(String)

  public var description: String {
    switch self {
    case let .unreadableRCFile(underlyingError):
      return "Unreadable RC File " + underlyingError
    }
  }
}

public protocol Defaultable {
  static var defaultValue: Self { get }
}

extension Configuration: Defaultable {
  public static var defaultValue: Configuration {
    return Configuration()
  }
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
    _ = Defaults.queryHistoryLocation(configuration)
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
      var format: FBiOSTargetFormat?

      if let rcContents = try? String(contentsOf: DefaultsRCFile) {
        let rcTokens = Arguments.fromString(rcContents)
        let (_, result) = try rcFileParser.parse(rcTokens)
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

  fileprivate static var rcFileParser: Parser<(Configuration?, FBiOSTargetFormat?)> {
    return Parser
      .ofTwoSequenced(
        Configuration.parser.optional(),
        FBiOSTargetFormatParsers.parser.optional()
      )
  }

  fileprivate static func queryHistoryLocation(_ configuration: Configuration) -> URL {
    let setPath = configuration.deviceSetPath ?? FBSimulatorControlConfiguration.defaultDeviceSetPath()
    return URL.urlRelativeTo(setPath, component: ".fbsimctl_last_query", isDirectory: false)
  }
}

extension Action {
  var defaultQuery: FBiOSTargetQuery? {
    // Use reasonable defaults for each action.
    // Depending on what state the simulator is expected to be in.
    // Descructive of machine-killing actions shouldn't have defaults.
    switch self {
    case let .coreFuture(future) where type(of: future).futureType == .diagnosticQuery:
      return FBiOSTargetQuery.allTargets()
    case .list:
      return FBiOSTargetQuery.allTargets()
    case let .coreFuture(future):
      return type(of: future).futureType.defaultQuery
    case .delete:
      return nil
    case .listen:
      fallthrough
    default:
      return FBiOSTargetQuery.state(.booted)
    }
  }
}

extension FBiOSTargetFutureType {
  var defaultQuery: FBiOSTargetQuery? {
    switch self {
    case FBiOSTargetFutureType.boot:
      return nil
    default:
      return FBiOSTargetQuery.state(.booted)
    }
  }
}
