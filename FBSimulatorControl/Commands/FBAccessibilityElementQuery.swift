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
///
/// This is the framework-level equivalent of the point-or-marker target that
/// CLIs (sime2e, idb) expose, decoupled from any argument parser so both can
/// share a single resolution path.
public enum FBAccessibilityElementQuery: Equatable, Sendable {
  case point(CGPoint)
  /// An element whose `key` value *contains* `value` — a substring match, not an equality test, so
  /// `"General"` finds an element labelled `"General Settings"`. Every backend matches the same way;
  /// the first element found in tree order wins.
  ///
  /// `depth` bounds how deep the search descends and is honoured by the accessibility backend, which
  /// walks the live element tree. The XCUI-grade backends read a whole tree in one round trip (under
  /// their own read bounds) and match over the result, so they do not apply it.
  case marker(value: String, key: FBAXSearchableKey, depth: UInt)
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
    case let .marker(value, key, _):
      return .marker(value: value, matchKey: key.rawValue)
    case .frontmost:
      return .frontmost
    case let .application(pid):
      return .application(pid: pid)
    }
  }
}
