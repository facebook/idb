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

  /// Reads the whole bounded attribute tree the query targets and returns it parsed. `.frontmost`
  /// resolves the foreground app; `.application` anchors on the given pid; `.marker` reads the frontmost
  /// tree so the shared matcher can find the element in the serialized result.
  ///
  /// Returns the raw read rather than serialized elements so `describeTree` serializes exactly once,
  /// with the caller's keys/format/filter — none of which belong on a raw read, since the guest reads
  /// the whole bounded tree and key selection happens at serialize. `FBAXTreeRead` also carries the
  /// fullscreen-modal descriptor the read surfaced (host-facing enrichment, not serialized) and whether
  /// the guest's walk was truncated.
  func readRawTree(for query: FBAccessibilityElementQuery) async throws -> FBAXTreeRead

  /// Warns that a read's tree was truncated by the depth or node bound, so an incomplete tree is never
  /// passed off as whole. Per backend because each logs through its own target; `describeTree` calls it
  /// once per describe, and never on the `.marker` wait poll, which reads without describing.
  func warnIfTruncated(_ truncated: Bool) async
}

extension FBAXTreeReader {

  /// `describe` for any tree-reading backend: resolve what the query means, read the raw tree, warn if it
  /// was truncated, serialize it once with the caller's keys/format/filter, and wrap. A point delegates to
  /// the backend's targeted `hitTest` and turns an empty result into an error, which is what makes
  /// `describe(.point:)` throwing while `hitTest` stays optional. Serialize and warn live here — not
  /// behind `readRawTree` — so they run once per describe and not on a `.marker` wait poll that reads
  /// without describing.
  func describeTree(
    _ query: FBAccessibilityElementQuery,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse {
    switch query {
    case let .point(point):
      guard let response = try await hitTest(at: point, options: options) else {
        throw FBUIAutomationError.noElementAtPoint(backend: backend, x: Double(point.x), y: Double(point.y))
      }
      // A hit-test resolves one element with no tree behind it, so there is no screen or truncation to
      // report — only which backend answered and what was asked for.
      return response.withProvenance(backend: backend.documentName, target: query.targetDescriptor)
    case let .marker(value, key, _):
      let read = try await readRawTree(for: query)
      await warnIfTruncated(read.truncated)
      let elements = FBAXTreeWalk.describeAllElements(
        fromTree: read.tree, keys: options.serializationKeys(including: [key.serializationKey]), nestedFormat: false, pid: read.pid, filter: .all
      )
      guard let match = FBAXTreeWalk.matchingElement(inElements: elements, markerValue: value, key: key) else {
        throw FBUIAutomationError.elementNotFound(backend: backend, key: key.rawValue, value: value)
      }
      return FBAccessibilityElementsResponse(elements: .single(match), modal: read.modal)
        .withProvenance(
          backend: backend.documentName,
          target: query.targetDescriptor,
          screen: FBAXTreeWalk.screenInfo(fromTree: read.tree),
          truncated: read.truncated
        )
    case .frontmost, .application:
      let read = try await readRawTree(for: query)
      await warnIfTruncated(read.truncated)
      let elements = FBAXTreeWalk.describeAllElements(
        fromTree: read.tree, keys: options.serializationKeys, nestedFormat: options.nestedFormat, pid: read.pid, filter: options.filter
      )
      return FBAccessibilityElementsResponse(elements: .tree(elements), modal: read.modal)
        .withProvenance(
          backend: backend.documentName,
          target: query.targetDescriptor,
          screen: FBAXTreeWalk.screenInfo(fromTree: read.tree),
          truncated: read.truncated
        )
    }
  }
}
