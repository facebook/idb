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

/// The two command-executor reads this handler drives. Extracted as a seam so the handler's
/// request→options→executor wiring can be tested against a recording double: `FBIDBCommandExecutor`
/// is a `public final class` with no other injection point, and the options handed across this
/// boundary are the only place a request field dropped between the wire and the reader is
/// observable.
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

  /// The request→executor core, lifted out of `handle` so it can be exercised without a
  /// `GRPCAsyncServerCallContext` (a GRPC framework type the companion never constructs and `handle`
  /// does not read) and against an `AccessibilityDescribing` double.
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
