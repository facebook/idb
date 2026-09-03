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
/// the shared schema.
///
// SAFETY: holds only an immutable reference to the target; each verb resolves and closes its own
// element handle, so no mutable state is shared across calls, and the target's accessibility request
// path is async IPC already safe under concurrent use. `Sendable` lets a caller hold one reader.
// patternlint-disable-next-line unchecked-sendable
final class FBAccessibilityUIAutomation: FBUIAutomation, @unchecked Sendable {

  private let simulator: FBSimulator

  private var operations: any AccessibilityOperations { simulator }

  init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  func describe(
    _ query: FBAccessibilityElementQuery,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse {
    try await Self.translatingBackendErrors(query) {
      let element = try await operations.resolveElement(for: query)
      defer { element.close() }
      let response = try await element.serialize(with: options)
        .withProvenance(backend: FBUIAutomationBackend.accessibility.name, target: query.targetDescriptor)
      // A point or marker resolves one element and is then serialized through the frontmost path, which
      // reads screen bounds off whatever element it is handed. For those queries that element is the
      // match rather than the application root, so the bounds it reports describe the match — they have
      // to be discarded, and replaced where the read does know better.
      switch query {
      case .point:
        return response.replacingScreen(nil)
      case .marker:
        return response.replacingScreen(element.rootBounds.flatMap(FBAXTranslationRequest.screenInfo(fromBounds:)))
      case .frontmost, .application:
        return response
      }
    }
  }

  /// Re-raises the accessibility stack's "element not found" as the backend-neutral
  /// `FBUIAutomationError`, so a caller holding `any FBUIAutomation` can catch it without knowing
  /// which backend it holds. Every other accessibility failure is transport-specific and passes
  /// through untouched.
  private static func translatingBackendErrors<T>(
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
      return try await element.serialize(with: options)
        .withProvenance(backend: FBUIAutomationBackend.accessibility.name, target: .point(point))
    } catch let error as FBAccessibilityError {
      // A point that resolves to no element is a valid empty hit-test result, not a failure.
      if case .elementNotFound = error { return nil }
      throw error
    }
  }

  func tap(
    _ query: FBAccessibilityElementQuery,
    options: FBTapOptions
  ) async throws {
    // AXPress is instantaneous with nowhere to put a hold; reject `duration` rather than silently
    // downgrading a long-press to a tap.
    guard options.duration == nil else {
      throw FBUIAutomationError.operationUnsupported(backend: .accessibility, operation: "A tap with a hold duration")
    }
    try await Self.translatingBackendErrors(query) {
      let element = try await operations.resolveElement(for: query)
      defer { element.close() }
      if let assertion = options.assertion {
        let actual = try await element.stringValue(forSearchableKey: assertion.key)
        guard actual == assertion.value else {
          throw FBUIAutomationError.valueMismatch(
            backend: .accessibility, key: assertion.key.rawValue, expected: assertion.value, actual: actual
          )
        }
      }
      try await element.tap()
    }
  }

  func setValue(_ value: String, for query: FBAccessibilityElementQuery) async throws {
    try await Self.translatingBackendErrors(query) {
      let element = try await operations.resolveElement(for: query)
      defer { element.close() }
      try await element.setValue(value)
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
    try await Self.translatingBackendErrors(query) {
      let element = try await operations.resolveElement(for: query)
      defer { element.close() }
      try await element.scroll(with: direction)
    }
  }

  func frame(_ query: FBAccessibilityElementQuery) async throws -> CGRect {
    try await Self.translatingBackendErrors(query) {
      let element = try await operations.resolveElement(for: query)
      defer { element.close() }
      return try await element.frame()
    }
  }

  /// Resolves both endpoints to screen points and synthesizes the gesture over HID. There is no
  /// accessibility action for a drag — `AXPress` is the only write this path has — so the endpoints
  /// are all this backend contributes, and the touches go the same way every other backend sends them.
  func drag(
    from source: FBAccessibilityElementQuery,
    to destination: FBAccessibilityElementQuery,
    options: FBDragOptions
  ) async throws {
    let start = try await endpoint(source)
    let end = try await endpoint(destination)
    try await simulator.sendHIDGesture(
      .drag(
        Double(start.x), yStart: Double(start.y), xEnd: Double(end.x), yEnd: Double(end.y),
        delta: options.delta, pressDuration: options.pressDuration, duration: options.duration,
        releaseDuration: options.releaseDuration
      )
    )
  }

  /// The screen point a drag endpoint names: a coordinate is itself, a marker is the centre of the
  /// element's frame.
  private func endpoint(_ query: FBAccessibilityElementQuery) async throws -> CGPoint {
    switch try FBDragEndpoint(query, backend: .accessibility) {
    case let .point(point):
      return point
    case .marker:
      let frame = try await frame(query)
      return CGPoint(x: frame.midX, y: frame.midY)
    }
  }
}
