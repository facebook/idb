/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public enum BridgeServeOptions {
  public static func idleTimeout(arguments: [String], fallback: Int32) -> Int32 {
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
        NSLog("[BridgeServer] ignoring unusable %@ '%@'; using %ds", flag, value, fallback)
      } else {
        NSLog("[BridgeServer] ignoring unusable %@ '%@'", flag, value)
      }
      return fallback
    }
    return seconds
  }

  public static func exitOnDisconnect(arguments: [String]) -> Bool {
    (firstValue(for: "--exit-on-disconnect", in: arguments) as NSString?)?.boolValue ?? false
  }

  // Serve options use the first duplicate, unlike accessibility request flags.
  private static func firstValue(for flag: String, in arguments: [String]) -> String? {
    for index in stride(from: 0, to: max(0, arguments.count - 1), by: 2) {
      if arguments[index] == flag {
        return arguments[index + 1]
      }
    }
    return nil
  }
}
