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

struct AccessibilityInfoMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_AccessibilityInfoRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_AccessibilityInfoResponse {
    let format = AccessibilityInfoRequestTranslation.outputFormat(from: request.format)
    let backend = AccessibilityInfoRequestTranslation.backend(from: request.backend)
    // A marker selects a single element to describe; without one the request
    // describes the element at a point, or the whole frontmost app.
    if let query = AccessibilityInfoRequestTranslation.markerQuery(from: request) {
      let data = try await commandExecutor.accessibility_describe(query: query, format: format, backend: backend)
      return .with {
        $0.json = String(data: data, encoding: .utf8) ?? ""
      }
    }
    let options = try AccessibilityInfoRequestTranslation.options(from: request, format: format)
    let response = try await commandExecutor.accessibility_info_at_point(
      AccessibilityInfoRequestTranslation.point(from: request), options: options, backend: backend)
    let jsonData = try AccessibilityInfoRequestTranslation.legacyJSON(from: response)
    return .with {
      $0.json = String(data: jsonData, encoding: .utf8) ?? ""
    }
  }
}
