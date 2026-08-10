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

/// The pure translation from an `accessibility_info` request to the framework's query and option
/// types, and from a read's response to the legacy output bytes. Free of the command executor so the
/// wire contract is pinned by unit tests without a target; the method handler stays a thin dispatcher.
enum AccessibilityInfoRequestTranslation {

  /// The marker query a request selects, or nil when the request targets a point or the whole
  /// frontmost app.
  static func markerQuery(from request: Idb_AccessibilityInfoRequest) -> FBAccessibilityElementQuery? {
    guard !request.marker.isEmpty else {
      return nil
    }
    return .marker(value: request.marker, key: searchableKey(from: request.matchKey), depth: UInt(request.depth))
  }

  /// The point a request targets, or nil for the whole frontmost app.
  static func point(from request: Idb_AccessibilityInfoRequest) -> NSValue? {
    guard request.hasPoint else {
      return nil
    }
    return NSValue(point: .init(x: request.point.x, y: request.point.y))
  }

  /// The request options for a point / frontmost read. Rejects an all-invalid `--key` list rather
  /// than silently falling back to the default set and masking the caller's typo; an empty list means
  /// "defaults", and unrecognized keys in a partially-valid list are dropped.
  static func options(from request: Idb_AccessibilityInfoRequest, format: FBAccessibilityOutputFormat) throws -> FBAccessibilityRequestOptions {
    let mappedKeys = Set(request.keys.compactMap { FBAXKeys(rawValue: $0) })
    if !request.keys.isEmpty && mappedKeys.isEmpty {
      throw GRPCStatus(
        code: .invalidArgument,
        message: "no recognized accessibility keys in \(request.keys)")
    }
    let keys = mappedKeys.isEmpty ? FBAXKeys.defaultSet : mappedKeys
    return FBAccessibilityRequestOptions(
      format: format,
      keys: keys,
      enableLogging: true,
      enableProfiling: request.profile,
      collectFrameCoverage: request.collectFrameCoverage)
  }

  /// The backend a request selects, through the framework's name bijection. `UNSPECIFIED` — an older
  /// client, or one that did not ask — and an unrecognized value from a newer client both preserve the
  /// historical CoreSimulator path rather than failing the call.
  static func backend(from wire: Idb_AccessibilityInfoRequest.Backend) -> FBUIAutomationBackend {
    switch wire {
    case .unspecified:
      return .accessibility
    case .ax:
      return FBUIAutomationBackend(.ax)
    case .axbridge:
      return FBUIAutomationBackend(.axBridge)
    case .axbridgePersistent:
      return FBUIAutomationBackend(.axBridgePersistent)
    case .UNRECOGNIZED:
      return .accessibility
    }
  }

  /// The wire format the request asked for. `LEGACY` is the flat array the gRPC surface has always
  /// returned by default; an unrecognized value from a newer client falls back to it rather than
  /// failing the call.
  static func outputFormat(from format: Idb_AccessibilityInfoRequest.Format) -> FBAccessibilityOutputFormat {
    switch format {
    case .legacy:
      return .default
    case .nested:
      return .nested
    case .complete:
      return .complete
    case .UNRECOGNIZED:
      return .default
    }
  }

  static func searchableKey(from key: Idb_AccessibilityActionRequest.SearchableKey) -> FBAXSearchableKey {
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

  /// The historical byte shape of a point / frontmost read: the bare element array, serialized without
  /// sorted keys — distinct from the marker path's `{"elements": …}` envelope.
  static func legacyJSON(from response: FBAccessibilityElementsResponse) throws -> Data {
    try JSONSerialization.data(withJSONObject: response.elements.legacyFoundationObject)
  }

  /// The response bytes for a point / frontmost read: the historical bare shape for the legacy
  /// formats, byte-untouched, and the consolidated document for `complete`.
  static func responseJSON(from response: FBAccessibilityElementsResponse, format: FBAccessibilityOutputFormat) throws -> Data {
    switch format {
    case .default, .nested:
      return try legacyJSON(from: response)
    case .complete:
      return try response.formattedOutputJSON(format: format)
    }
  }
}
