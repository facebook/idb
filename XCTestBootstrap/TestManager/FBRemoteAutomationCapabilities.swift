/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The capabilities the guest daemon advertises in response to
/// `_XCTD_exchangeCapabilities:`, keyed by capability name to its supported version.
///
/// The concrete key set is owned by the daemon and varies by OS, so this is a thin,
/// honest wrapper over the returned dictionary rather than a fixed enumeration. Net-new
/// remote-only features gate on `supports(_:minimumVersion:)`.
public struct FBRemoteAutomationCapabilities: Sendable, Equatable {

  public let entries: [String: Int]

  public init(entries: [String: Int]) {
    self.entries = entries
  }

  public static let empty = FBRemoteAutomationCapabilities(entries: [:])

  /// Whether the daemon advertises `capability` at `minimumVersion` or greater.
  public func supports(_ capability: String, minimumVersion: Int = 1) -> Bool {
    guard let version = entries[capability] else {
      return false
    }
    return version >= minimumVersion
  }

  /// Parses the raw `_XCTD_exchangeCapabilities:` response into a typed value.
  ///
  /// The daemon returns a dictionary of capability name to an integer version; entries
  /// with non-string keys or non-numeric values are ignored.
  static func parse(_ response: Any?) -> FBRemoteAutomationCapabilities {
    guard let dictionary = response as? [AnyHashable: Any] else {
      return .empty
    }
    var entries: [String: Int] = [:]
    for (key, value) in dictionary {
      guard let name = key as? String, let number = value as? NSNumber else {
        continue
      }
      entries[name] = number.intValue
    }
    return FBRemoteAutomationCapabilities(entries: entries)
  }
}
