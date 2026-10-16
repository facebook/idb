/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBSimulatorAX
import FBSimulatorControl
import Foundation
import GRPCCore
import IDBGRPCSwift

/// Seam over the five `CompanionAccessibility` actions this handler drives, so the request-to-action
/// wiring can be tested against a double.
protocol AccessibilityActing {
  func accessibilityWait(
    query: AccessibilityElementQuery,
    backend: UIAutomationBackend,
    timeout: TimeInterval,
    pollInterval: TimeInterval
  ) async throws

  func accessibilityTap(
    query: AccessibilityElementQuery,
    backend: UIAutomationBackend,
    expectedValue: String?,
    expectedKey: AXSearchableKey
  ) async throws

  func accessibilityScroll(
    query: AccessibilityElementQuery,
    backend: UIAutomationBackend,
    direction: AccessibilityScrollDirection
  ) async throws

  func accessibilitySetValue(
    query: AccessibilityElementQuery,
    backend: UIAutomationBackend,
    value: String
  ) async throws

  func accessibilityDrag(
    from source: AccessibilityElementQuery,
    to destination: AccessibilityElementQuery,
    backend: UIAutomationBackend,
    options: DragOptions
  ) async throws
}

struct AccessibilityActionMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_AccessibilityActionRequest, context: ServerContext) async throws -> Idb_AccessibilityActionResponse {
    try await Self.respond(to: request, using: commandExecutor.accessibility)
  }

  /// Lifted out of `handle` so it can be tested without a `ServerContext`.
  static func respond(
    to request: Idb_AccessibilityActionRequest,
    using commandExecutor: any AccessibilityActing
  ) async throws -> Idb_AccessibilityActionResponse {
    switch try AccessibilityActionRequestTranslation.action(from: request) {
    case let .wait(query, backend, timeout, pollInterval):
      return try await AccessibilityActionRequestTranslation.waitResponse {
        try await commandExecutor.accessibilityWait(query: query, backend: backend, timeout: timeout, pollInterval: pollInterval)
      }
    case let .tap(query, backend, expectedValue, expectedKey):
      try await commandExecutor.accessibilityTap(
        query: query, backend: backend, expectedValue: expectedValue, expectedKey: expectedKey)
    case let .scroll(query, backend, direction):
      try await commandExecutor.accessibilityScroll(query: query, backend: backend, direction: direction)
    case let .setValue(query, backend, value):
      try await commandExecutor.accessibilitySetValue(query: query, backend: backend, value: value)
    case let .drag(source, destination, backend, options):
      try await commandExecutor.accessibilityDrag(
        from: source, to: destination, backend: backend, options: options)
    }
    return .init()
  }
}
