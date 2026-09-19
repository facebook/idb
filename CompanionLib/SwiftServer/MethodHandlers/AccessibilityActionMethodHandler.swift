/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBSimulatorControl
import Foundation
import GRPCCore
import IDBGRPCSwift

/// Seam over the five `IDBCommandExecutor` actions this handler drives, so the request-to-action
/// wiring can be tested against a double.
protocol AccessibilityActing {
  func accessibility_wait(
    query: AccessibilityElementQuery,
    backend: UIAutomationBackend,
    timeout: TimeInterval,
    pollInterval: TimeInterval
  ) async throws

  func accessibility_tap(
    query: AccessibilityElementQuery,
    expectedValue: String?,
    expectedKey: AXSearchableKey
  ) async throws

  func accessibility_scroll(query: AccessibilityElementQuery, direction: AccessibilityScrollDirection) async throws

  func accessibility_set_value(query: AccessibilityElementQuery, value: String) async throws

  func accessibility_drag(
    from source: AccessibilityElementQuery,
    to destination: AccessibilityElementQuery,
    options: DragOptions
  ) async throws
}

extension IDBCommandExecutor: AccessibilityActing {}

struct AccessibilityActionMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_AccessibilityActionRequest, context: ServerContext) async throws -> Idb_AccessibilityActionResponse {
    try await Self.respond(to: request, using: commandExecutor)
  }

  /// Lifted out of `handle` so it can be tested without a `ServerContext`.
  static func respond(
    to request: Idb_AccessibilityActionRequest,
    using commandExecutor: any AccessibilityActing
  ) async throws -> Idb_AccessibilityActionResponse {
    switch try AccessibilityActionRequestTranslation.action(from: request) {
    case let .wait(query, backend, timeout, pollInterval):
      return try await AccessibilityActionRequestTranslation.waitResponse {
        try await commandExecutor.accessibility_wait(query: query, backend: backend, timeout: timeout, pollInterval: pollInterval)
      }
    case let .tap(query, expectedValue, expectedKey):
      try await commandExecutor.accessibility_tap(query: query, expectedValue: expectedValue, expectedKey: expectedKey)
    case let .scroll(query, direction):
      try await commandExecutor.accessibility_scroll(query: query, direction: direction)
    case let .setValue(query, value):
      try await commandExecutor.accessibility_set_value(query: query, value: value)
    case let .drag(source, destination, options):
      try await commandExecutor.accessibility_drag(from: source, to: destination, options: options)
    }
    return .init()
  }
}
