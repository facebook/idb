/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBControlCore
import FBSimulatorControl
import Foundation
import GRPC
import IDBGRPCSwift

/// Seam over the two `FBIDBCommandExecutor` reads this handler drives, so the request-to-options wiring
/// can be tested against a double.
protocol AccessibilityDescribing {
  func accessibility_describe(
    query: FBAccessibilityElementQuery,
    options: FBAccessibilityRequestOptions,
    backend: FBUIAutomationBackend
  ) async throws -> Data

  func accessibility_info_at_point(
    _ value: NSValue?,
    options: FBAccessibilityRequestOptions,
    backend: FBUIAutomationBackend
  ) async throws -> FBAccessibilityElementsResponse
}

extension FBIDBCommandExecutor: AccessibilityDescribing {}

struct AccessibilityInfoMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_AccessibilityInfoRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_AccessibilityInfoResponse {
    try await Self.respond(to: request, using: commandExecutor)
  }

  /// Lifted out of `handle` so it can be tested without a `GRPCAsyncServerCallContext`.
  static func respond(
    to request: Idb_AccessibilityInfoRequest,
    using commandExecutor: any AccessibilityDescribing
  ) async throws -> Idb_AccessibilityInfoResponse {
    try AccessibilityInfoRequestTranslation.validate(request)
    let format = AccessibilityInfoRequestTranslation.outputFormat(from: request.format)
    let backend = AccessibilityInfoRequestTranslation.backend(from: request.backend)
    // Built before the branch: both paths are reads of the same tree with the same options, so the
    // marker path honours the request's keys, profiling and frame coverage too.
    let options = try AccessibilityInfoRequestTranslation.options(from: request, format: format)
    // A marker selects a single element to describe; without one the request
    // describes the element at a point, or the whole frontmost app.
    if let query = AccessibilityInfoRequestTranslation.markerQuery(from: request) {
      let data = try await commandExecutor.accessibility_describe(query: query, options: options, backend: backend)
      return .with {
        $0.json = String(data: data, encoding: .utf8) ?? ""
      }
    }
    let response = try await commandExecutor.accessibility_info_at_point(
      AccessibilityInfoRequestTranslation.point(from: request), options: options, backend: backend)
    let jsonData = try AccessibilityInfoRequestTranslation.responseJSON(from: response, format: format)
    return .with {
      $0.json = String(data: jsonData, encoding: .utf8) ?? ""
    }
  }
}
