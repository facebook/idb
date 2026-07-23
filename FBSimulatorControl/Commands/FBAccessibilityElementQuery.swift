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
public enum FBAccessibilityElementQuery: Equatable {
  case point(CGPoint)
  case marker(value: String, key: FBAXSearchableKey, depth: UInt)
  case frontmost
}

extension AccessibilityOperations {

  /// Resolves a query to a concrete accessibility element, dispatching to the
  /// point / matching / frontmost primitives. Callers own the returned element
  /// and must `close()` it.
  public func accessibilityElement(
    for query: FBAccessibilityElementQuery
  ) async throws -> FBAccessibilityElement {
    switch query {
    case let .point(point):
      return try await accessibilityElement(at: point)
    case let .marker(value, key, depth):
      return try await accessibilityElementMatching(value: value, forKey: key, depth: depth)
    case .frontmost:
      return try await accessibilityElementForFrontmostApplication()
    }
  }

  /// Resolves a query and serializes the element to canonical sorted-keys JSON,
  /// always closing the element. Shared by the describe / describe-find /
  /// describe-point paths so every front-end emits an identical serialization.
  public func accessibilityDescribe(
    for query: FBAccessibilityElementQuery,
    options: FBAccessibilityRequestOptions
  ) async throws -> Data {
    let element = try await accessibilityElement(for: query)
    defer { element.close() }
    let response = try element.serialize(with: options)
    return try JSONSerialization.data(
      withJSONObject: response.asDictionary(), options: .sortedKeys
    )
  }
}
