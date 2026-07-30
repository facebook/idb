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
/// matched against a searchable key up to a depth, or the frontmost application.
///
/// This is the framework-level equivalent of the point-or-marker target that
/// CLIs (sime2e, idb) expose, decoupled from any argument parser so both can
/// share a single resolution path.
public enum FBAccessibilityElementQuery: Equatable, Sendable {
  case point(CGPoint)
  case marker(value: String, key: FBAXSearchableKey, depth: UInt)
  case frontmost
}

/// Thrown by the accessibility `tap` when an element's value for the checked key
/// does not equal the caller's expected value.
public struct FBAccessibilityExpectedValueMismatch: Error, CustomStringConvertible {
  public let key: FBAXSearchableKey
  public let expected: String
  public let actual: String

  public var description: String {
    "Element \(key.rawValue) does not match expected value \"\(expected)\". Actual: \"\(actual)\""
  }
}
