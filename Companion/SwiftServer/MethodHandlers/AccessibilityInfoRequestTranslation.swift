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
  ///
  /// `ignore_case` reaches the marker as well as `match`: it is a property of how the read compares
  /// strings, not of which of the two verbs asked for the comparison. An older client leaves it false,
  /// which is the historical case-sensitive resolution.
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
  ///
  /// Shares `match_key` with the marker read, which already names "which attribute the search compares
  /// against"; an unrecognized key falls back to `AXLabel`, as `searchableKey(from:)` does everywhere
  /// else.
  static func match(from request: Idb_AccessibilityInfoRequest) -> FBAccessibilityMatch? {
    FBAccessibilityMatch(
      value: request.match,
      key: searchableKey(from: request.matchKey),
      ignoresCase: request.ignoreCase)
  }

  /// The element filter a request selects. `FILTER_ALL` — an older client, or one that did not ask —
  /// and an unrecognized value from a newer client both preserve the historical unfiltered read rather
  /// than failing the call, as `backend(from:)` and `outputFormat(from:)` do.
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

  /// Rejects a request that sets both `marker` and `match`.
  ///
  /// They are different verbs sharing a message: `marker` selects one element and fails when there is
  /// none, `match` narrows a list and reports an empty one. There is no reading of "both" that is not a
  /// guess about which the caller meant, so this is `INVALID_ARGUMENT` rather than a precedence rule.
  static func validate(_ request: Idb_AccessibilityInfoRequest) throws {
    guard request.marker.isEmpty || request.match.isEmpty else {
      throw GRPCStatus(code: .invalidArgument, message: "set either marker or match, not both")
    }
  }

  /// The backend a request selects, through the framework's name bijection. `UNSPECIFIED` — an older
  /// client, or one that did not ask — and an unrecognized value from a newer client both preserve the
  /// historical CoreSimulator path rather than failing the call.
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
