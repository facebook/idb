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

  /// Resolves a query and performs an accessibility tap (AXPress). When
  /// `expectedValue` is given, the element's value for `expectedKey` must equal
  /// it first, otherwise `FBAccessibilityExpectedValueMismatch` is thrown.
  /// Always closes the element.
  public func accessibilityTap(
    for query: FBAccessibilityElementQuery,
    expectedValue: String? = nil,
    expectedKey: FBAXSearchableKey = .label
  ) async throws {
    let element = try await accessibilityElement(for: query)
    defer { element.close() }
    if let expectedValue {
      let actual = try element.stringValue(forSearchableKey: expectedKey)
      guard actual == expectedValue else {
        throw FBAccessibilityExpectedValueMismatch(
          key: expectedKey, expected: expectedValue, actual: actual
        )
      }
    }
    try element.tap()
  }
}

/// Thrown by `accessibilityTap` when an element's value for the checked key does
/// not equal the caller's expected value.
public struct FBAccessibilityExpectedValueMismatch: Error, CustomStringConvertible {
  public let key: FBAXSearchableKey
  public let expected: String
  public let actual: String

  public var description: String {
    "Element \(key.rawValue) does not match expected value \"\(expected)\". Actual: \"\(actual)\""
  }
}
