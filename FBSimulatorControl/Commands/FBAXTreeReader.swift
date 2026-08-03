/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import Foundation

/// A backend that answers a query by reading a whole `XC_kAXXC*` attribute tree and matching over the
/// result — the shape both XCUI-grade backends share.
///
/// What actually differs between them is narrow: where the tree comes from (a `testmanagerd` session
/// versus a guest reader) and how a point is hit-tested. Everything above that — deciding what a query
/// means, flattening the tree, matching a marker, wrapping the response, and choosing the error — is
/// identical, so it is written once here rather than once per backend.
protocol FBAXTreeReader: FBUIAutomation {
  /// Which backend this is, for the errors the shared verbs raise.
  nonisolated var backend: FBUIAutomationBackend { get }

  /// Reads the tree the query targets and flattens it to the shared schema. `.frontmost` resolves the
  /// foreground app; `.application` anchors on the given pid; `.marker` reads the frontmost tree and
  /// lets the shared matcher find the element in the result.
  ///
  /// The flattening happens behind this call rather than after it because the raw attribute tree is a
  /// bag of `Any` and cannot leave a backend's isolation; the serialized elements can. Also returns any
  /// fullscreen-modal descriptor the read surfaced (host-facing enrichment, not serialized) — `nil`
  /// when no modal is present or the backend does not report one.
  func readElements(
    for query: FBAccessibilityElementQuery,
    keys: Set<FBAXKeys>,
    nestedFormat: Bool,
    filter: FBAccessibilityElementFilter
  ) async throws -> (elements: [FBJSONValue], modal: FBAccessibilityModalInfo?)
}

extension FBAXTreeReader {

  /// `describe` for any tree-reading backend: resolve what the query means, read, serialize, and wrap.
  /// A point delegates to the backend's targeted `hitTest` and turns an empty result into an error,
  /// which is what makes `describe(.point:)` throwing while `hitTest` stays optional.
  func describeTree(
    _ query: FBAccessibilityElementQuery,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse {
    switch query {
    case let .point(point):
      guard let response = try await hitTest(at: point, options: options) else {
        throw FBUIAutomationError.noElementAtPoint(backend: backend, x: Double(point.x), y: Double(point.y))
      }
      return response
    case let .marker(value, key, _):
      let read = try await readElements(for: query, keys: options.keys.union([key.serializationKey]), nestedFormat: false, filter: .all)
      guard let match = FBAXTreeSerialization.matchingElement(inElements: read.elements, markerValue: value, key: key) else {
        throw FBUIAutomationError.elementNotFound(backend: backend, key: key.rawValue, value: value)
      }
      return FBAccessibilityElementsResponse(elements: match, modal: read.modal)
    case .frontmost, .application:
      let read = try await readElements(
        for: query, keys: options.keys, nestedFormat: options.nestedFormat, filter: options.filter
      )
      return FBAccessibilityElementsResponse(elements: .array(read.elements), modal: read.modal)
    }
  }
}
