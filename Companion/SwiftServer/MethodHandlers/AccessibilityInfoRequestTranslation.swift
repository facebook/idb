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

/// Translates an `accessibility_info` request to the framework's query and option types, and a read's
/// response to the legacy output bytes.
enum AccessibilityInfoRequestTranslation {

  /// The marker query a request selects, or nil when the request targets a point or the whole frontmost
  /// app. An unset `ignore_case` (older clients) is the historical case-sensitive match.
  static func markerQuery(from request: Idb_AccessibilityInfoRequest) -> FBAccessibilityElementQuery? {
    guard !request.marker.isEmpty else {
      return nil
    }
    return .marker(
      value: request.marker,
      key: searchableKey(from: request.matchKey),
      depth: UInt(request.depth),
      ignoresCase: request.ignoreCase)
  }

  /// The substring narrowing a request asks for, or nil when it asks for none.
  static func match(from request: Idb_AccessibilityInfoRequest) -> FBAccessibilityMatch? {
    FBAccessibilityMatch(
      value: request.match,
      key: searchableKey(from: request.matchKey),
      ignoresCase: request.ignoreCase)
  }

  /// `FILTER_ALL` and an unrecognized value both mean the unfiltered read.
  static func filter(from wire: Idb_AccessibilityInfoRequest.Filter) -> FBAccessibilityElementFilter {
    switch wire {
    case .all:
      return .all
    case .interactable:
      return .interactable
    case .UNRECOGNIZED:
      return .all
    }
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
  /// "defaults", and unrecognized keys in a partially-valid list are dropped. `--key all` expands to
  /// every key the reader can answer.
  static func options(from request: Idb_AccessibilityInfoRequest, format: FBAccessibilityOutputFormat) throws -> FBAccessibilityRequestOptions {
    let mappedKeys = FBAXKeys.requested(request.keys)
    if !request.keys.isEmpty && mappedKeys.isEmpty {
      throw GRPCStatus(
        code: .invalidArgument,
        message: "no recognized accessibility keys in \(request.keys)")
    }
    let keys = mappedKeys.isEmpty ? FBAXKeys.defaultSet : mappedKeys
    return FBAccessibilityRequestOptions(
      format: format,
      keys: keys,
      enableLogging: false,
      enableProfiling: request.profile,
      collectFrameCoverage: request.collectFrameCoverage,
      filter: filter(from: request.filter),
      match: match(from: request))
  }

  /// `marker` selects one element; `match` narrows a list. Setting both is rejected rather than given a
  /// precedence.
  static func validate(_ request: Idb_AccessibilityInfoRequest) throws {
    guard request.marker.isEmpty || request.match.isEmpty else {
      throw GRPCStatus(code: .invalidArgument, message: "set either marker or match, not both")
    }
  }

  /// `UNSPECIFIED` and an unrecognized value both fall back to the CoreSimulator backend.
  static func backend(from wire: Idb_AccessibilityInfoRequest.Backend) -> FBUIAutomationBackend {
    switch wire {
    case .unspecified:
      return .accessibility
    case .ax:
      return FBUIAutomationBackend(resolvedName: .ax)
    case .axbridge, .axbridgePersistent:
      // The companion owns its simulator for its whole run, so it holds a bridge. Holding the shared
      // one would make every other process on this machine wait and then spawn a duplicate.
      return FBUIAutomationBackend(resolvedName: .axBridgeExclusive)
    case .UNRECOGNIZED:
      return .accessibility
    }
  }

  /// An unrecognized value falls back to `LEGACY`, the flat array the gRPC surface has always returned.
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
