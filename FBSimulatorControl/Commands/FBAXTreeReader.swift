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
/// Backends differ only in where the tree comes from (a `testmanagerd` session versus a guest reader)
/// and how a point is hit-tested; query semantics, marker matching, response wrapping and errors are
/// shared here.
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
  ///
  /// `strategy` chooses how the tree is traversed, and therefore which vocabulary answers. Per read: the
  /// same caller wants the structural tree for one question and the semantic one for another.
  func readRawTree(
    for query: FBAccessibilityElementQuery,
    attributes: [String]?,
    explainUnreachable: Bool,
    strategy: FBAXTraversalStrategy
  ) async throws -> FBAXTreeRead

  /// Warns that the traversal could not answer keys the caller asked for, so a caller can tell "this read
  /// could not ask" from "the app set nothing".
  func warnIfUnsatisfiable(_ keys: Set<FBAXKeys>, strategy: FBAXTraversalStrategy) async

  /// Warns that a read's tree was truncated by the depth or node bound, so an incomplete tree is never
  /// passed off as whole. Per backend because each logs through its own target; `describeTree` calls it
  /// once per describe, and never on the `.marker` wait poll, which reads without describing.
  func warnIfTruncated(_ truncated: Bool) async

  /// Warns when a whole-tree read asked for reachability. Guest lanes only: the translator lane has no
  /// counterpart for these attributes, so the same request costs nothing there.
  func warnIfReachabilityAcrossTree(_ keys: Set<FBAXKeys>) async

  /// Warns that most of a read's elements carry no rectangle, which can mean the target is serving stale
  /// cached children. Per backend for the same reason as `warnIfTruncated` — each logs through its own
  /// target — and called only on a whole-tree describe, since a single element has no ratio to judge.
  func warnIfMostElementsUnframed(_ frames: FBAccessibilityFrameSummary?) async

  /// Where this read spent its time, in whatever shape this backend measures. Nil from a backend that
  /// does not measure, which is distinct from a zeroed profile.
  func profile(
    for read: FBAXTreeRead, elementCount: Int, serializeDuration: CFAbsoluteTime
  ) -> FBAccessibilityProfile?
}

extension FBAXTreeReader {

  /// Elements in the serialized read, counted through `children`.
  ///
  /// The `complete` format is always nested, so the top level is a single root and `count` would report 1
  /// for any tree — where the translator lane counts every node.
  static func nodeCount(of elements: [FBAccessibilityDocumentElement]) -> Int {
    elements.reduce(0) { $0 + 1 + nodeCount(of: $1.children ?? []) }
  }

  /// Backends that do not measure report nothing rather than zeroes.
  func profile(
    for read: FBAXTreeRead, elementCount: Int, serializeDuration: CFAbsoluteTime
  ) -> FBAccessibilityProfile? {
    nil
  }
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
      let read = try await readRawTree(
        for: query, attributes: FBAXWire.Node.fetchList(for: markerKeys),
        explainUnreachable: false, strategy: options.traversalStrategy
      )
      await warnIfTruncated(read.truncated)
      await warnIfUnsatisfiable(
        options.unsatisfiableKeys(including: [key.serializationKey]), strategy: options.traversalStrategy
      )
      // A marker read walks the whole tree to find one element, so it costs the same per-node
      // hit-testing a describe-all does while returning far less.
      await warnIfReachabilityAcrossTree(markerKeys)
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
      let read = try await readRawTree(
        for: query,
        attributes: FBAXWire.Node.fetchList(for: options.serializationKeys),
        // Only a read that asked to name what is in the way pays for the guest to work it out.
        explainUnreachable: options.keys.contains(.occludedBy),
        strategy: options.traversalStrategy
      )
      await warnIfTruncated(read.truncated)
      await warnIfUnsatisfiable(options.unsatisfiableKeys, strategy: options.traversalStrategy)
      await warnIfReachabilityAcrossTree(options.serializationKeys)
      let serializeStarted = CFAbsoluteTimeGetCurrent()
      let walked = FBAXTreeWalk.describeAllElements(
        fromTree: read.tree, keys: options.serializationKeys, nestedFormat: options.nestedFormat, pid: read.pid
      )
      let screen = FBAXTreeWalk.screenInfo(fromTree: read.tree)
      let elements = try await refiningInteractable(
        options.filter.apply(to: walked), screen: screen, options: options
      )
      // Measures serialize + refine, closed before response assembly.
      let serializeDuration = CFAbsoluteTimeGetCurrent() - serializeStarted
      // Coverage is a calculation over the serialized model, the same one every backend runs.
      // Remote-content discovery is accessibility-only, so `additional` stays absent here.
      let coverage: FBAccessibilityCoverage? =
        options.collectFrameCoverage
        ? screen.flatMap {
          .measured(
            reported: elements, walked: walked, screenBounds: FBAccessibilityCoverage.bounds(of: $0),
            nested: options.nestedFormat
          )
        } : nil
      // Judged on the reported elements — what the caller's `--filter` shows them.
      await warnIfMostElementsUnframed(FBAccessibilityFrameSummary(elements: elements))
      return FBAccessibilityElementsResponse(
        elements: .tree(elements),
        profilingData: options.enableProfiling
          ? profile(
            for: read, elementCount: Self.nodeCount(of: elements), serializeDuration: serializeDuration
          ) : nil,
        coverage: coverage, modal: read.modal, automation: read.automation
      )
      .withProvenance(
        backend: backend.name,
        target: query.targetDescriptor,
        screen: screen,
        truncated: read.truncated
      )
    }
  }

  /// Refines each blocked element's reasons with the two pieces of context a single element does not
  /// carry: the screen bounds (whether the edge is clipping it) and the guest's hit-test answer
  /// (`explainedBy`, naming what is covering it or which relative handles the touch).
  ///
  /// The hit-test answer arrived with the tree, so nothing here costs a round trip; a missing answer
  /// leaves the reason unenriched rather than failing the read. Runs after the filter, and neither
  /// refinement changes an element's `status` — only which reasons it carries.
  private func refiningInteractable(
    _ elements: [FBAccessibilityDocumentElement],
    screen: FBAccessibilityScreenInfo?,
    options: FBAccessibilityRequestOptions
  ) async throws -> [FBAccessibilityDocumentElement] {
    guard options.keys.contains(.occludedBy) || screen != nil else {
      return elements
    }
    var refined: [FBAccessibilityDocumentElement] = []
    refined.reserveCapacity(elements.count)
    for element in elements {
      refined.append(await refiningInteractable(of: element, ancestors: [], screen: screen, options: options))
    }
    return refined
  }

  private func refiningInteractable(
    of element: FBAccessibilityDocumentElement,
    ancestors: [FBAXElementIdentity],
    screen: FBAccessibilityScreenInfo?,
    options: FBAccessibilityRequestOptions
  ) async -> FBAccessibilityDocumentElement {
    var element = element
    let ancestryForChildren = ancestors + [FBAXElementIdentity(element)]
    if let children = element.children {
      var refined: [FBAccessibilityDocumentElement] = []
      refined.reserveCapacity(children.count)
      for child in children {
        refined.append(
          await refiningInteractable(of: child, ancestors: ancestryForChildren, screen: screen, options: options)
        )
      }
      element.children = refined
    }
    // Screen-edge clipping first: pure geometry, no round trip.
    element = FBAXScreenBoundsClassifier.notingScreenClipping(element, screen: screen)
    guard options.keys.contains(.occludedBy) else {
      return element
    }
    guard case let .blocked(reasons)?? = element.interactable else {
      return element
    }
    // The guest already hit-tested this element's centre during its walk and sent the answer back with
    // the tree, so there is nothing to ask for here — only an answer to interpret. That is the whole
    // difference between one round trip and one per unreachable element.
    guard let found = element.explainedBy else {
      return element
    }
    let foundIdentity = FBAXElementIdentity(found)
    // Whether the element that took the touch is a relative decides which answer this is. A relative
    // means the element was never independently interactive — a label inside its button, or a container
    // passing through to its child — and the caller should act on that relative. Anything else is
    // genuinely in the way.
    let isRelative =
      ancestors.contains(foundIdentity) || Self.descendantIdentities(of: element).contains(foundIdentity)
    element.interactable = .some(
      .blocked(
        reasons: reasons.map { reason in
          switch reason {
          case .occluded(nil), .notHittable:
            return isRelative ? .handledBy(found) : .occluded(by: found)
          default:
            return reason
          }
        }
      )
    )
    return element
  }

  /// The identities of everything below `element`, for recognising a hit result as its own descendant.
  private static func descendantIdentities(of element: FBAccessibilityDocumentElement) -> Set<FBAXElementIdentity> {
    var identities: Set<FBAXElementIdentity> = []
    func visit(_ children: [FBAccessibilityDocumentElement]?) {
      for child in children ?? [] {
        identities.insert(FBAXElementIdentity(child))
        visit(child.children)
      }
    }
    visit(element.children)
    return identities
  }

  /// Resolves a query to the point a write acts on, plus the assertion that keeps a two-step write honest.
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
      // Structural traversal regardless of what a read would have asked for: resolving a write target is
      // about finding the element to act on, and the semantic traversal cannot name element types.
      let read = try await readRawTree(
        for: query, attributes: nil, explainUnreachable: false, strategy: .viewHierarchy
      )
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

  /// What an unoccupied write target means, told in the terms the caller used to name it: a marker
  /// write reports `elementMoved`, and only a caller who named a coordinate is told about a coordinate.
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
  /// This is `describeTree` asking for the frame key alone. Narrowing to `.frameDict` optimises the
  /// serialization, not the read — the guest walks the whole bounded tree either way.
  ///
  /// A whole-tree query answers with the application root's frame, matching what the accessibility
  /// backend reports for the same query: a flat walk lists the root first, and `.point`/`.marker` answer
  /// with the single element they resolved, so the head of the response is the named element in
  /// every case.
  func frameFromTree(_ query: FBAccessibilityElementQuery) async throws -> CGRect {
    let response = try await describeTree(query, options: FBAccessibilityRequestOptions(keys: [.frameDict]))
    // Throws rather than substituting a zero rect, which a caller could not tell apart from an element
    // genuinely at the origin.
    guard let element = response.elements.elements.first,
      let frame = element.frame ?? nil,
      let x = frame.x, let y = frame.y, let width = frame.width, let height = frame.height
    else {
      throw FBUIAutomationError.frameUnavailable(backend: backend, query: query)
    }
    return CGRect(x: x, y: y, width: width, height: height)
  }
}

/// Noting where the screen edge, rather than another element, is part of why something cannot be reached.
enum FBAXScreenBoundsClassifier {

  /// Adds `clippedByScreen` to a blocked element whose frame is not wholly within the screen.
  ///
  /// Accumulates rather than replaces: clipping and occlusion are not alternatives, and an element
  /// scrolled under a navigation bar is usually both. Blocked case only — an actionable element
  /// already carries a reachable point.
  static func notingScreenClipping(
    _ element: FBAccessibilityDocumentElement,
    screen: FBAccessibilityScreenInfo?
  ) -> FBAccessibilityDocumentElement {
    guard let screen,
      case let .blocked(reasons)?? = element.interactable,
      !reasons.contains(.clippedByScreen), // idempotent: ordering is guaranteed at encode, not here
      let frame = (element.frame ?? nil)?.rect,
      frame.minX < 0 || frame.minY < 0 || frame.maxX > screen.width || frame.maxY > screen.height
    else {
      return element
    }
    var element = element
    element.interactable = .some(.blocked(reasons: (reasons + [.clippedByScreen]).mostSpecificFirst))
    return element
  }
}

/// What makes two serialized elements the same element, for recognising a hit-test result inside the tree
/// it came from.
///
/// A hit-test resolves an element with no identity that outlives the call, so identity has to be
/// reconstructed from what both sides can see: what it is, what it is called, and where it sits. The frame
/// is what does most of the work — type and label repeat freely across a screen, geometry rarely does.
struct FBAXElementIdentity: Hashable {
  private let type: String?
  private let identifier: String?
  private let label: String?
  private let frame: [Double]

  /// The element as the guest described whatever answered a hit-test.
  init(_ reference: FBAccessibilityElementRef) {
    self.init(
      type: reference.type, identifier: reference.identifier, label: reference.label,
      rect: reference.frame?.rect)
  }

  init(_ element: FBAccessibilityDocumentElement) {
    self.init(
      type: element.type ?? nil, identifier: element.identifier ?? nil,
      label: element.label ?? nil, rect: (element.frame ?? nil)?.rect)
  }

  private init(type: String?, identifier: String?, label: String?, rect: CGRect?) {
    self.type = type
    self.identifier = identifier
    self.label = label
    // Rounded, because the two reads reach the same coordinate by different arithmetic and an exact
    // Double comparison would make identity depend on the last bit.
    self.frame =
      rect.map { r -> [Double] in
        [Double(r.minX), Double(r.minY), Double(r.width), Double(r.height)].map { (($0 * 100).rounded()) / 100 }
      } ?? []
  }
}
