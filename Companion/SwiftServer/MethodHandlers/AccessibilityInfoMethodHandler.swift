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
    let nested = request.format == .nested
    // A marker selects a single element to describe; without one the request
    // describes the element at a point, or the whole frontmost app.
    if !request.marker.isEmpty {
      let query: FBAccessibilityElementQuery = .marker(
        value: request.marker, key: searchableKey(from: request.matchKey), depth: UInt(request.depth))
      let data = try await commandExecutor.accessibility_describe(query: query, nested: nested)
      return .with {
        $0.json = String(data: data, encoding: .utf8) ?? ""
      }
    }
    var point: NSValue?
    if request.hasPoint {
      point = NSValue(point: .init(x: request.point.x, y: request.point.y))
    }
    // Reject an all-invalid --key list rather than silently falling back to the
    // default set and masking the caller's typo; an empty list means "defaults".
    let mappedKeys = Set(request.keys.compactMap { FBAXKeys(rawValue: $0) })
    if !request.keys.isEmpty && mappedKeys.isEmpty {
      throw GRPCStatus(
        code: .invalidArgument,
        message: "no recognized accessibility keys in \(request.keys)")
    }
    let keys = mappedKeys.isEmpty ? FBAXKeys.defaultSet : mappedKeys
    let options = FBAccessibilityRequestOptions(
      nestedFormat: nested,
      keys: keys,
      enableLogging: true,
      enableProfiling: false,
      collectFrameCoverage: false)
    let response = try await commandExecutor.accessibility_info_at_point(point, options: options)
    let jsonData = try JSONSerialization.data(withJSONObject: response.elements)
    return .with {
      $0.json = String(data: jsonData, encoding: .utf8) ?? ""
    }
  }

  private func searchableKey(from key: Idb_AccessibilityActionRequest.SearchableKey) -> FBAXSearchableKey {
    switch key {
    case .label:
      return .label
    case .uniqueID:
      return .uniqueID
    case .value:
      return .value
    case .title:
      return .title
    case .role:
      return .role
    case .roleDescription:
      return .roleDescription
    case .subrole:
      return .subrole
    case .help:
      return .help
    case .placeholder:
      return .placeholder
    case .UNRECOGNIZED:
      return .label
    }
  }
}
