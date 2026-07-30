/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// The `FBUIAutomation` backend over the CoreSimulator accessibility-translation path. Resolves a
/// query to an `FBAccessibilityElement` via the accessibility primitives and serializes it through
/// the shared schema — the same handle-based mechanism the accessibility command surface has always
/// used, expressed as the converged verb set.
final class FBAccessibilityUIAutomation: FBUIAutomation {

  private let operations: any AccessibilityOperations

  init(operations: any AccessibilityOperations) {
    self.operations = operations
  }

  func describe(
    _ query: FBAccessibilityElementQuery,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse {
    let element = try await resolveElement(for: query)
    defer { element.close() }
    return try element.serialize(with: options)
  }

  func tap(
    _ query: FBAccessibilityElementQuery,
    expectedValue: String?,
    expectedKey: FBAXSearchableKey
  ) async throws {
    let element = try await resolveElement(for: query)
    defer { element.close() }
    if let expectedValue {
      let actual = try element.stringValue(forSearchableKey: expectedKey)
      guard actual == expectedValue else {
        throw FBAccessibilityExpectedValueMismatch(key: expectedKey, expected: expectedValue, actual: actual)
      }
    }
    try element.tap()
  }

  func setValue(_ value: String, for query: FBAccessibilityElementQuery) async throws {
    let element = try await resolveElement(for: query)
    defer { element.close() }
    try element.setValue(value)
  }

  func wait(
    _ query: FBAccessibilityElementQuery,
    timeout: TimeInterval,
    pollInterval: TimeInterval
  ) async throws {
    guard case let .marker(markerValue, key, depth) = query else {
      throw FBAccessibilityError.waitRequiresMarker
    }
    let found = try await FBUIAutomationPolling.pollUntilFound(
      timeout: timeout,
      pollInterval: pollInterval,
      clock: { Date().timeIntervalSinceReferenceDate },
      sleep: { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    ) { () -> Bool? in
      do {
        let element = try await operations.accessibilityElementMatching(value: markerValue, forKey: key, depth: depth)
        element.close()
        return true
      } catch let error as FBAccessibilityError {
        // The matcher throws `.elementNotFound` when the element isn't in the tree yet — keep
        // polling on that alone, and surface every other failure (boot/dispatcher/IPC) at once.
        if case .elementNotFound = error {
          return nil
        }
        throw error
      }
    }
    if found == nil {
      throw FBAccessibilityError.waitTimedOut(key: key.rawValue, value: markerValue, timeout: timeout)
    }
  }

  func scroll(_ query: FBAccessibilityElementQuery, direction: FBAccessibilityScrollDirection) async throws {
    let element = try await resolveElement(for: query)
    defer { element.close() }
    try element.scroll(with: direction)
  }

  func frame(_ query: FBAccessibilityElementQuery) async throws -> CGRect {
    let element = try await resolveElement(for: query)
    defer { element.close() }
    return try element.frame()
  }

  // MARK: - Element resolution

  /// Resolves a query to a concrete accessibility element via the point / matching / frontmost
  /// primitives. Callers own the returned element and must `close()` it.
  private func resolveElement(for query: FBAccessibilityElementQuery) async throws -> FBAccessibilityElement {
    switch query {
    case let .point(point):
      return try await operations.accessibilityElement(at: point)
    case let .marker(value, key, depth):
      return try await operations.accessibilityElementMatching(value: value, forKey: key, depth: depth)
    case .frontmost:
      return try await operations.accessibilityElementForFrontmostApplication()
    }
  }
}
