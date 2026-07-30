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

  /// Resolves a query and serializes the element to canonical sorted-keys JSON.
  /// Shim onto the accessibility `FBUIAutomation` backend, which owns the read
  /// logic; kept only while callers migrate to `uiAutomation(backend:)`.
  public func accessibilityDescribe(
    for query: FBAccessibilityElementQuery,
    options: FBAccessibilityRequestOptions
  ) async throws -> Data {
    try await FBAccessibilityUIAutomation(operations: self).describeJSON(query, options: options)
  }

  /// Resolves a query and performs an accessibility tap (AXPress), optionally asserting the element's
  /// value for `expectedKey` first (else `FBAccessibilityExpectedValueMismatch`). Shim onto the
  /// accessibility `FBUIAutomation` backend; kept only while callers migrate to `uiAutomation(backend:)`.
  public func accessibilityTap(
    for query: FBAccessibilityElementQuery,
    expectedValue: String? = nil,
    expectedKey: FBAXSearchableKey = .label
  ) async throws {
    try await FBAccessibilityUIAutomation(operations: self).tap(query, expectedValue: expectedValue, expectedKey: expectedKey)
  }

  /// Resolves a query and scrolls the element in the given direction. Shim onto the accessibility
  /// `FBUIAutomation` backend; kept only while callers migrate to `uiAutomation(backend:)`.
  public func accessibilityScroll(
    for query: FBAccessibilityElementQuery,
    direction: FBAccessibilityScrollDirection
  ) async throws {
    try await FBAccessibilityUIAutomation(operations: self).scroll(query, direction: direction)
  }

  /// Resolves a query and sets the element's accessibility value. Shim onto the accessibility
  /// `FBUIAutomation` backend; kept only while callers migrate to `uiAutomation(backend:)`.
  public func accessibilitySetValue(
    for query: FBAccessibilityElementQuery,
    value: String
  ) async throws {
    try await FBAccessibilityUIAutomation(operations: self).setValue(value, for: query)
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
