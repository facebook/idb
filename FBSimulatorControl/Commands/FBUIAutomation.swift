/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Selects the backend a UI-automation element operation runs against.
public enum FBUIAutomationBackend: Sendable {
  /// The legacy CoreSimulator accessibility-translation path.
  case accessibility
  /// The bundle-free guest `testmanagerd` remote-automation channel (iOS 27+).
  case remoteAutomation
}

/// The converged UI-automation surface: element reads and element-targeted
/// actions, expressed once against an `FBAccessibilityElementQuery` target and run by the selected
/// backend. `FBSimulator.uiAutomation(backend:)` vends the backend that implements it.
///
/// Consumers (sime2e, the idb companion) map their own flag/enum to an `FBUIAutomationBackend`, build
/// an `FBAccessibilityElementQuery`, and call one verb — rather than re-implementing per-backend
/// dispatch, the pid-probe anchor, or the keys default themselves. Each backend already funnels into
/// the shared serializer/schema, so the response is identical in shape across backends.
public protocol FBUIAutomation {

  /// Reads the element(s) named by `query` and serializes them to the shared accessibility schema.
  /// `.point`/`.marker` yield a single element; `.frontmost` yields the whole tree.
  func describe(
    _ query: FBAccessibilityElementQuery,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse

  /// Taps the element named by `query`. `.point` taps the coordinate; `.marker` finds the element and
  /// taps its centre. `expectedValue`, when given, asserts the element's value for `expectedKey`
  /// before tapping — accessibility only; ignored over remote automation. `.frontmost` taps the
  /// frontmost element over accessibility but is rejected over remote automation.
  func tap(
    _ query: FBAccessibilityElementQuery,
    expectedValue: String?,
    expectedKey: FBAXSearchableKey
  ) async throws

  /// Sets `value` on the element named by `query`. `.point`/`.marker` targets only.
  func setValue(
    _ value: String,
    for query: FBAccessibilityElementQuery
  ) async throws
}

public extension FBUIAutomation {

  /// Taps the element named by `query` with no value assertion.
  func tap(_ query: FBAccessibilityElementQuery) async throws {
    try await tap(query, expectedValue: nil, expectedKey: .label)
  }

  /// `describe`, serialized to canonical sorted-keys JSON — the form CLI front-ends emit.
  func describeJSON(
    _ query: FBAccessibilityElementQuery,
    options: FBAccessibilityRequestOptions
  ) async throws -> Data {
    let response = try await describe(query, options: options)
    return try JSONSerialization.data(withJSONObject: response.asDictionary(), options: .sortedKeys)
  }
}

public extension FBSimulator {

  /// The converged UI-automation surface for `backend` — element reads and element-targeted
  /// actions over a single query-shaped API. `.remoteAutomation` is the memoized `testmanagerd`
  /// session; `.accessibility` is the CoreSimulator translation path.
  func uiAutomation(backend: FBUIAutomationBackend) throws -> any FBUIAutomation {
    switch backend {
    case .accessibility:
      return FBAccessibilityUIAutomation(operations: self)
    case .remoteAutomation:
      return try remoteAutomation()
    }
  }
}
