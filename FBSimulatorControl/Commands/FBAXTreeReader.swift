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
  /// `attributes` names what the guest fetches per element, or nil to leave it on its default list.
  /// Derived from the caller's requested keys, so an attribute only reaches the wire when a key that
  /// needs it was asked for.
  func readRawTree(for query: FBAccessibilityElementQuery, attributes: [String]?) async throws -> FBAXTreeRead

  /// Warns that a read's tree was truncated by the depth or node bound, so an incomplete tree is never
  /// passed off as whole. Per backend because each logs through its own target; `describeTree` calls it
  /// once per describe, and never on the `.marker` wait poll, which reads without describing.
  func warnIfTruncated(_ truncated: Bool) async
}

/// Where a point-addressed write lands, and what the element there must still be for it to go ahead.
struct FBAXWriteTarget: Equatable {
  let point: CGPoint
  /// The application to hit-test within, or nil to resolve the owning app from the point itself.
  let pid: pid_t?
  let assertion: FBAXBridgeWriteAssertion?
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
      return response.withProvenance(backend: backend.name, target: query.targetDescriptor)
    case let .marker(value, key, _):
      let markerKeys = options.serializationKeys(including: [key.serializationKey])
      let read = try await readRawTree(for: query, attributes: FBAXWire.Node.fetchList(for: markerKeys))
      await warnIfTruncated(read.truncated)
      let elements = FBAXTreeWalk.describeAllElements(
        fromTree: read.tree, keys: markerKeys, nestedFormat: false, pid: read.pid
      )
      guard let match = FBAXTreeWalk.matchingElement(inElements: elements, markerValue: value, key: key) else {
        throw FBUIAutomationError.elementNotFound(backend: backend, key: key.rawValue, value: value)
      }
      // The match came from a flattened walk, so it carries no children of its own; reporting them
      // keeps a marker read the same shape as any other single-element read of the same format.
      let matched = options.nestedFormat ? match.reportingChildren() : match
      return FBAccessibilityElementsResponse(elements: .single(matched), modal: read.modal)
        .withProvenance(
          backend: backend.name,
          target: query.targetDescriptor,
          screen: FBAXTreeWalk.screenInfo(fromTree: read.tree),
          truncated: read.truncated
        )
    case .frontmost, .application:
      let read = try await readRawTree(for: query, attributes: FBAXWire.Node.fetchList(for: options.serializationKeys))
      await warnIfTruncated(read.truncated)
      let walked = FBAXTreeWalk.describeAllElements(
        fromTree: read.tree, keys: options.serializationKeys, nestedFormat: options.nestedFormat, pid: read.pid
      )
      let elements = options.filter.apply(to: walked)
      let screen = FBAXTreeWalk.screenInfo(fromTree: read.tree)
      // Coverage is a calculation over the serialized model, so it is the same one the accessibility
      // backend runs — a whole-tree read reports it whichever backend served it. Remote-content
      // discovery is accessibility-only, so `additional` stays absent here.
      let coverage: FBAccessibilityCoverage? =
        options.collectFrameCoverage
        ? screen.flatMap {
          .measured(
            reported: elements, walked: walked, screenBounds: FBAccessibilityCoverage.bounds(of: $0),
            nested: options.nestedFormat
          )
        } : nil
      return FBAccessibilityElementsResponse(elements: .tree(elements), coverage: coverage, modal: read.modal)
        .withProvenance(
          backend: backend.name,
          target: query.targetDescriptor,
          screen: screen,
          truncated: read.truncated
        )
    }
  }

  /// Resolves a query to the point a write acts on, plus the assertion that keeps a two-step write honest.
  ///
  /// Shared for the same reason `describeTree` is: deciding what a query means, matching a marker and
  /// choosing the error are identical whoever performs the write, and only the performing differs.
  ///
  /// `.point` goes straight through — a coordinate names no element, so there is nothing to assert about
  /// it and nothing to read first. `.marker` reads the tree, matches, and takes the matched element's
  /// centre, deriving its assertion from the element it actually found rather than from the marker
  /// string: markers match by substring, so asserting the caller's text would refuse every marker that is
  /// a prefix of the label it matched.
  ///
  /// Whole-tree queries are refused. A point-addressed write acts on the deepest element under the point,
  /// so "the frontmost application" would silently become "whatever sits in the middle of the screen" —
  /// not the element the accessibility backend acts on for the same query, and not one the caller named.
  func writeTarget(
    for query: FBAccessibilityElementQuery,
    operation: String,
    callerAssertion: FBTapOptions.Assertion? = nil
  ) async throws -> FBAXWriteTarget {
    switch query {
    case let .point(point):
      if let callerAssertion {
        // The caller asked for a value to be checked and a bare coordinate carries none, so the element
        // has to be read first — the one case a point write costs two round trips instead of one.
        try await assertBeforeWriting(callerAssertion, atPoint: point)
      }
      return FBAXWriteTarget(point: point, pid: nil, assertion: nil)
    case let .marker(value, key, _):
      let read = try await readRawTree(for: query, attributes: nil)
      await warnIfTruncated(read.truncated)
      // Unfiltered, like the marker branch of `describeTree`: a write resolves the element the caller
      // named, and a caller's `--filter` is about what a read reports, not about what exists to act on.
      let elements = FBAXTreeWalk.describeAllElements(
        fromTree: read.tree,
        keys: FBAXKeys.defaultSet.union([key.serializationKey]),
        nestedFormat: false,
        pid: read.pid
      )
      guard let match = FBAXTreeWalk.matchingElement(inElements: elements, markerValue: value, key: key) else {
        throw FBUIAutomationError.elementNotFound(backend: backend, key: key.rawValue, value: value)
      }
      if let callerAssertion {
        let actual = match.searchableValue(for: callerAssertion.key) ?? ""
        guard actual == callerAssertion.value else {
          throw FBUIAutomationError.valueMismatch(
            backend: backend, key: callerAssertion.key.rawValue, expected: callerAssertion.value, actual: actual
          )
        }
      }
      switch FBAXTreeWalk.resolveMarker(inElements: elements, markerValue: value, key: key) {
      case let .resolved(x, y):
        return FBAXWriteTarget(
          point: CGPoint(x: x, y: y),
          pid: read.pid,
          assertion: Self.derivedAssertion(from: match, key: key)
        )
      case .offScreen:
        throw FBUIAutomationError.elementNotOnScreen(backend: backend, key: key.rawValue, value: value)
      case .notFound:
        throw FBUIAutomationError.elementNotFound(backend: backend, key: key.rawValue, value: value)
      }
    case .frontmost, .application:
      throw FBUIAutomationError.pointOrMarkerRequired(backend: backend, operation: operation)
    }
  }

  /// What an unoccupied write target means, told in the terms the caller used to name it.
  ///
  /// A marker write is reported as its element having moved, the same as when something *else* is found
  /// under the point. Both are the screen changing between the read that resolved the marker and the
  /// write that acted on it, so reporting one of them against coordinates the caller never chose would
  /// make one condition look like two. Only a caller who named a coordinate is told about a coordinate.
  func emptyWriteTargetError(for query: FBAccessibilityElementQuery, at point: CGPoint) -> FBUIAutomationError {
    guard case let .marker(value, key, _) = query else {
      return .noElementAtPoint(backend: backend, x: Double(point.x), y: Double(point.y))
    }
    return .elementMoved(backend: backend, key: key.rawValue, value: value)
  }

  /// The assertion a marker write carries: the attribute the marker searched on, and the value the
  /// element it matched actually reports for it. Nil when this wire carries no such attribute, in which
  /// case the write goes unasserted rather than not at all.
  private static func derivedAssertion(
    from match: FBAccessibilityDocumentElement,
    key: FBAXSearchableKey
  ) -> FBAXBridgeWriteAssertion? {
    guard let node = FBAXWire.Node(assertableSearchKey: key), let actual = match.searchableValue(for: key) else {
      return nil
    }
    return FBAXBridgeWriteAssertion(key: node, value: actual)
  }

  /// Checks a caller's pre-write assertion against the element at a point, which needs a read of its own
  /// — unlike a marker write, which already holds the element it resolved.
  private func assertBeforeWriting(_ assertion: FBTapOptions.Assertion, atPoint point: CGPoint) async throws {
    let options = FBAccessibilityRequestOptions(keys: FBAXKeys.defaultSet.union([assertion.key.serializationKey]))
    guard let response = try await hitTest(at: point, options: options),
      let element = response.elements.elements.first
    else {
      throw FBUIAutomationError.noElementAtPoint(backend: backend, x: Double(point.x), y: Double(point.y))
    }
    let actual = element.searchableValue(for: assertion.key) ?? ""
    guard actual == assertion.value else {
      throw FBUIAutomationError.valueMismatch(
        backend: backend, key: assertion.key.rawValue, expected: assertion.value, actual: actual
      )
    }
  }

  /// `frame` for a tree-reading backend: the rectangle of the element a query names, in points.
  ///
  /// Geometry is an attribute of the tree, so this is `describeTree` asking for the frame key alone —
  /// there is nothing to read that a describe does not already read, and no backend-specific step, which
  /// is why it composes here rather than once per backend. Narrowing the key set to `.frameDict` is not
  /// an optimisation of the read (the guest walks the whole bounded tree either way) but of the
  /// serialization, which would otherwise fetch fifteen attributes per node to answer about one.
  ///
  /// A whole-tree query answers with the application root's frame, matching what the accessibility
  /// backend reports for the same query: a flat walk lists the root first, and `.point`/`.marker` answer
  /// with the single element they resolved, so the head of the response is the named element in
  /// every case.
  func frameFromTree(_ query: FBAccessibilityElementQuery) async throws -> CGRect {
    let response = try await describeTree(query, options: FBAccessibilityRequestOptions(keys: [.frameDict]))
    // Requesting `.frameDict` is what makes the frame present, so the guard is on a response shape the
    // types permit rather than one a backend produces. It throws rather than substituting a zero rect,
    // which a caller could not tell apart from an element genuinely at the origin.
    guard let element = response.elements.elements.first,
      let frame = element.frame ?? nil,
      let x = frame.x, let y = frame.y, let width = frame.width, let height = frame.height
    else {
      throw FBUIAutomationError.frameUnavailable(backend: backend, query: query)
    }
    return CGRect(x: x, y: y, width: width, height: height)
  }
}
