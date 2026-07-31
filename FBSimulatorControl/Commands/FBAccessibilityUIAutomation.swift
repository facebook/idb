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
    try await Self.translatingSeamErrors(query) {
      let element = try await operations.resolveElement(for: query)
      defer { element.close() }
      return try element.serialize(with: options)
    }
  }

  /// Runs an accessibility resolution, re-raising the one failure that is a fact about the *query*
  /// rather than about this transport as the backend-neutral `FBUIAutomationError`. The AX stack
  /// raises its own rich error deep in the element walk; translating it here is what lets a caller
  /// holding `any FBUIAutomation` catch "not found" without knowing which backend it holds. Every
  /// other accessibility failure (dispatcher, SpringBoard, a closed handle) is transport-specific and
  /// passes through untouched.
  private static func translatingSeamErrors<T>(
    _ query: FBAccessibilityElementQuery,
    _ body: () async throws -> T
  ) async throws -> T {
    do {
      return try await body()
    } catch let error as FBAccessibilityError {
      guard case let .elementNotFound(key, value, _) = error else { throw error }
      throw FBUIAutomationError.elementNotFound(backend: .accessibility, key: key, value: value)
    }
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
    try await Self.translatingSeamErrors(query) {
      let element = try await operations.resolveElement(for: query)
      defer { element.close() }
      if let expectedValue {
        let actual = try element.stringValue(forSearchableKey: expectedKey)
        guard actual == expectedValue else {
          throw FBUIAutomationError.valueMismatch(
            backend: .accessibility, key: expectedKey.rawValue, expected: expectedValue, actual: actual
          )
        }
      }
      try element.tap()
    }
  }

  func setValue(_ value: String, for query: FBAccessibilityElementQuery) async throws {
    try await Self.translatingSeamErrors(query) {
      let element = try await operations.resolveElement(for: query)
      defer { element.close() }
      try element.setValue(value)
    }
  }

  func wait(
    _ query: FBAccessibilityElementQuery,
    timeout: TimeInterval,
    pollInterval: TimeInterval
  ) async throws {
    try await FBUIAutomationPolling.waitForMarker(
      query, backend: .accessibility, timeout: timeout, pollInterval: pollInterval
    ) { markerValue, key, depth in
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
  }

  func scroll(_ query: FBAccessibilityElementQuery, direction: FBAccessibilityScrollDirection) async throws {
    try await Self.translatingSeamErrors(query) {
      let element = try await operations.resolveElement(for: query)
      defer { element.close() }
      try element.scroll(with: direction)
    }
  }

  func frame(_ query: FBAccessibilityElementQuery) async throws -> CGRect {
    try await Self.translatingSeamErrors(query) {
      let element = try await operations.resolveElement(for: query)
      defer { element.close() }
      return try element.frame()
    }
  }
}
