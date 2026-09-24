/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc
public final class FBAXBridgeArguments: NSObject {
  @objc public static func request(action: String, arguments: [String]) -> [String: Any] {
    var request: [String: Any] = ["verb": action]
    // The CLI consumes pairs, ignores unknown/dangling flags, and lets the last duplicate win.
    for index in stride(from: 0, to: max(0, arguments.count - 1), by: 2) {
      let value = arguments[index + 1]
      let string = value as NSString
      switch arguments[index] {
      case "--pid": request["pid"] = string.intValue
      case "--max-depth": request["maxDepth"] = string.intValue
      case "--max-nodes": request["maxNodes"] = string.intValue
      case "--automation-mode": request["automationMode"] = string.boolValue
      case "--translator-vocabulary": request["translatorVocabulary"] = string.boolValue
      case "--snapshot-tree": request["snapshotTree"] = string.boolValue
      case "--explain-unreachable": request["explainUnreachable"] = string.boolValue
      case "--attributes": request["attributes"] = value.components(separatedBy: ",")
      case "--x": request["x"] = string.doubleValue
      case "--y": request["y"] = string.doubleValue
      case "--method": request["method"] = value
      case "--action": request["action"] = value
      case "--value": request["value"] = value
      case "--setting": request["setting"] = value
      case "--enabled":
        switch value {
        case "true": request["enabled"] = true
        case "false": request["enabled"] = false
        default: request["enabled"] = value
        }
      case "--assert-key": request["assertKey"] = value
      case "--assert-value": request["assertValue"] = value
      default: break
      }
    }
    return request
  }

  @objc public static func idleTimeout(arguments: [String], fallback: Int32) -> Int32 {
    timeout(arguments: arguments, flag: "--idle-timeout", fallback: fallback) ?? fallback
  }

  public static func startupTimeout(arguments: [String]) -> Int32? {
    timeout(arguments: arguments, flag: "--startup-timeout", fallback: nil)
  }

  private static func timeout(arguments: [String], flag: String, fallback: Int32?) -> Int32? {
    guard let value = firstValue(for: flag, in: arguments) else {
      return fallback
    }
    let scanner = Scanner(string: value)
    guard let seconds = scanner.scanInt32(), scanner.isAtEnd, seconds > 0 else {
      if let fallback {
        NSLog("[AccessibilityService] ignoring unusable %@ '%@'; using %ds", flag, value, fallback)
      } else {
        NSLog("[AccessibilityService] ignoring unusable %@ '%@'", flag, value)
      }
      return fallback
    }
    return seconds
  }

  @objc public static func exitOnDisconnect(arguments: [String]) -> Bool {
    (firstValue(for: "--exit-on-disconnect", in: arguments) as NSString?)?.boolValue ?? false
  }

  // Serve options have always used the first duplicate, unlike accessibility request flags.
  private static func firstValue(for flag: String, in arguments: [String]) -> String? {
    for index in stride(from: 0, to: max(0, arguments.count - 1), by: 2) {
      if arguments[index] == flag {
        return arguments[index + 1]
      }
    }
    return nil
  }
}
