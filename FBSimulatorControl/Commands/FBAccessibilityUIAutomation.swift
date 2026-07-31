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
///
// SAFETY: holds only an immutable reference to the target; each verb resolves and closes its own
// element handle, so no mutable state is shared across calls, and the target's accessibility request
// path is async IPC already safe under concurrent use. `Sendable` lets a caller hold one reader.
// patternlint-disable-next-line unchecked-sendable
final class FBAccessibilityUIAutomation: FBUIAutomation, @unchecked Sendable {

  private let operations: any AccessibilityOperations

  init(operations: any AccessibilityOperations) {
    self.operations = operations
  }

  func describe(
    _ query: FBAccessibilityElementQuery,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse {
    let element = try await operations.resolveElement(for: query)
    defer { element.close() }
    return try element.serialize(with: options)
  }

  func hitTest(
    at point: CGPoint,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse? {
    do {
      let element = try await operations.resolveElement(for: .point(point))
      defer { element.close() }
      return try element.serialize(with: options)
    } catch let error as FBAccessibilityError {
      // A point that resolves to no element is a valid empty hit-test result, not a failure.
      if case .elementNotFound = error { return nil }
      throw error
    }
  }

  func tap(
    _ query: FBAccessibilityElementQuery,
    expectedValue: String?,
    expectedKey: FBAXSearchableKey
  ) async throws {
    let element = try await operations.resolveElement(for: query)
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
    let element = try await operations.resolveElement(for: query)
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
        let element = try await operations.resolveElement(for: .marker(value: markerValue, key: key, depth: depth))
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
    let element = try await operations.resolveElement(for: query)
    defer { element.close() }
    try element.scroll(with: direction)
  }

  func frame(_ query: FBAccessibilityElementQuery) async throws -> CGRect {
    let element = try await operations.resolveElement(for: query)
    defer { element.close() }
    return try element.frame()
  }
}
