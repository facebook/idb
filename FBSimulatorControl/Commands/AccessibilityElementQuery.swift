/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import Foundation

/// A resolvable reference to an accessibility element: a screen point, a marker
/// matched against a searchable key up to a depth, the frontmost application, or a
/// specific application by process identifier.
public enum FBAccessibilityElementQuery: Equatable, Sendable {
  case point(CGPoint)
  /// An element whose `key` value *contains* `value` — a substring match, not an equality test, so
  /// `"General"` finds an element labelled `"General Settings"`. Every backend matches the same way;
  /// the first element found in tree order wins.
  ///
  /// `depth` bounds how deep the search descends and is honoured by the accessibility backend, which
  /// walks the live element tree. The axbridge backend reads a whole tree in one round trip (under its
  /// own read bounds) and matches over the result, so it does not apply it.
  ///
  /// `ignoresCase` defaults off and writes never set it, so a write cannot act on an element the caller
  /// did not name.
  case marker(value: String, key: FBAXSearchableKey, depth: UInt, ignoresCase: Bool = false)
  case frontmost
  /// A specific application's whole element tree, anchored by its process identifier — read regardless
  /// of what is frontmost (e.g. an app behind a system modal), unlike `frontmost`. Callers resolve a
  /// bundle id to a pid (`FBSimulator.processID(forBundleID:)`) before building this.
  case application(pid: pid_t)
}

public extension FBAccessibilityElementQuery {
  /// How this query appears in the `complete` output document. Every describe verb emits the same
  /// document shape, so this is what tells a consumer which verb produced the one it is holding.
  var targetDescriptor: FBAccessibilityTargetDescriptor {
    switch self {
    case let .point(point):
      return .point(point)
    case let .marker(value, key, _, _):
      return .marker(value: value, matchKey: key.rawValue)
    case .frontmost:
      return .frontmost
    case let .application(pid):
      return .application(pid: pid)
    }
  }
}

extension FBAccessibilityElementQuery: CustomStringConvertible {
  /// How this query names its target in an error a user reads, phrased as a noun so it reads inside a
  /// sentence. The machine-readable counterpart is `targetDescriptor`.
  public var description: String {
    switch self {
    case let .point(point):
      return "the element at (\(Double(point.x)), \(Double(point.y)))"
    case let .marker(value, key, _, ignoresCase):
      // Naming the case-insensitivity matters most in the failure: "no element whose AXLabel contains
      // "ok"" reads as a claim about the screen, when the caller wants to know whether "OK" was
      // considered.
      return "the element whose \(key.rawValue) contains \"\(value)\"\(ignoresCase ? " (ignoring case)" : "")"
    case .frontmost:
      return "the frontmost application"
    case let .application(pid):
      return "the application with pid \(pid)"
    }
  }
}
