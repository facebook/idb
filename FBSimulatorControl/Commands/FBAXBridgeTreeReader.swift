/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import Foundation

/// The axbridge read pipeline. The protocol boundary keeps transport responses and warnings injectable
/// in unit tests; production has one conformer, `FBAXBridgeUIAutomation`.
protocol FBAXBridgeTreeReader: FBUIAutomation {
  /// The resolved axbridge backend, used in response metadata and errors.
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
  /// `traversal` chooses how the tree is traversed, and therefore which attributes the elements carry. Per read: the
  /// same caller wants the structural tree for one question and the semantic one for another. Already
  /// resolved, so a backend never has to decide what an unchosen traversal means at the point of reading.
  func readRawTree(
    for query: FBAccessibilityElementQuery,
    attributes: [String]?,
    explainUnreachable: Bool,
    traversal: FBAXTraversal
  ) async throws -> FBAXTreeRead

  /// The traversal axbridge performs when the request does not select one.
  static func autoTraversal(for options: FBAccessibilityRequestOptions) -> FBAXTraversal

  /// Warns that the traversal could not answer keys the caller asked for, so a caller can tell "this read
  /// could not ask" from "the app set nothing".
  func warnIfUnsatisfiable(_ keys: Set<FBAXKeys>, traversal: FBAXTraversal) async

  /// Warns that a read's tree was truncated by the depth or node bound.
  func warnIfTruncated(_ truncated: Bool) async

  /// Warns when a whole-tree read asked for reachability.
  func warnIfReachabilityAcrossTree(_ keys: Set<FBAXKeys>) async

  /// Warns that most of a read's elements carry no rectangle.
  func warnIfMostElementsUnframed(_ frames: FBAccessibilityFrameSummary?) async

  /// Produces the axbridge profile for a completed read.
  func profile(
    for read: FBAXTreeRead, elementCount: Int, serializeDuration: CFAbsoluteTime,
    traversal: FBAXTraversal
  ) -> FBAccessibilityProfile?
}

extension FBAXBridgeTreeReader {

  /// The traversal a read actually gets: the explicit request or axbridge's automatic choice.
  static func resolvedTraversal(for options: FBAccessibilityRequestOptions) -> FBAXTraversal {
    options.traversalStrategy.traversal ?? autoTraversal(for: options)
  }

  private static func readPlan(
    for options: FBAccessibilityRequestOptions,
    including extraKeys: Set<FBAXKeys> = [],
    explainUnreachable: Bool
  ) -> FBAXBridgeReadPlan {
    FBAXBridgeReadPlan(
      options: options,
      serializationKeys: options.serializationKeys(including: extraKeys),
      traversal: resolvedTraversal(for: options),
      explainUnreachable: explainUnreachable
    )
  }
}

/// The derived values used throughout one axbridge tree read.
private struct FBAXBridgeReadPlan {
  let serializationKeys: Set<FBAXKeys>
  let attributes: [String]?
  let traversal: FBAXTraversal
  let unsatisfiableKeys: Set<FBAXKeys>
  let nestedFormat: Bool
  let collectFrameCoverage: Bool
  let enableProfiling: Bool
  let explainUnreachable: Bool

  init(
    options: FBAccessibilityRequestOptions,
    serializationKeys: Set<FBAXKeys>,
    traversal: FBAXTraversal,
    explainUnreachable: Bool
  ) {
    self.serializationKeys = serializationKeys
    self.attributes = FBAXWire.Node.fetchList(for: serializationKeys)
    self.traversal = traversal
    self.unsatisfiableKeys = serializationKeys.intersection(traversal.unsatisfiableKeys)
    self.nestedFormat = options.nestedFormat
    self.collectFrameCoverage = options.collectFrameCoverage
    self.enableProfiling = options.enableProfiling
    self.explainUnreachable = explainUnreachable
  }
}

extension FBAXBridgeTreeReader {

  /// Resolves the query, reads the raw tree, serializes it, and attaches response metadata.
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
    case let .marker(value, key, _, ignoresCase):
      let plan = Self.readPlan(for: options, including: [key.serializationKey], explainUnreachable: false)
      let read = try await readRawTree(
        for: query, attributes: plan.attributes,
        explainUnreachable: plan.explainUnreachable, traversal: plan.traversal
      )
      await warnIfTruncated(read.truncated)
      await warnIfUnsatisfiable(plan.unsatisfiableKeys, traversal: plan.traversal)
      // A marker read walks the whole tree to find one element, so it costs the same per-node
      // hit-testing a describe-all does while returning far less.
      await warnIfReachabilityAcrossTree(plan.serializationKeys)
      let elements = FBAXTreeWalk.describeAllElements(
        fromTree: read.tree, keys: plan.serializationKeys, nestedFormat: false, pid: read.pid
      )
      guard
        let match = FBAXTreeWalk.matchingElement(
          inElements: elements, markerValue: value, key: key, ignoresCase: ignoresCase
        )
      else {
        throw FBUIAutomationError.elementNotFound(backend: backend, key: key.rawValue, value: value)
      }
      // The match came from a flattened walk, so it carries no children of its own; reporting them
      // keeps a marker read the same shape as any other single-element read of the same format.
      let matched = plan.nestedFormat ? match.reportingChildren() : match
      return FBAccessibilityElementsResponse(elements: .single(matched), modal: read.modal)
        .withProvenance(
          backend: backend.name,
          target: query.targetDescriptor,
          screen: FBAXTreeWalk.screenInfo(fromTree: read.tree),
          truncated: read.truncated
        )
    case .frontmost, .application:
      let plan = Self.readPlan(
        for: options,
        explainUnreachable: options.keys.contains(.occludedBy)
      )
      // An explicit single fetch cannot answer reachability: the application hit-tests every node for
      // these keys, and a snapshot asking for them times out rather than answering. `.auto` routes such
      // a read to the per-node walk, so only an explicit choice can get here — refused up front rather
      // than left to time out in the guest.
      let unanswerable = plan.serializationKeys.intersection(FBAXKeys.reachabilityKeys)
      if plan.traversal == .singleFetch, !unanswerable.isEmpty {
        throw FBUIAutomationError.traversalCannotAnswer(
          backend: backend,
          traversal: FBAXTraversal.singleFetch.rawValue,
          keys: unanswerable.map(\.rawValue).sorted()
        )
      }
      let read = try await readRawTree(
        for: query,
        attributes: plan.attributes,
        explainUnreachable: plan.explainUnreachable,
        traversal: plan.traversal
      )
      await warnIfTruncated(read.truncated)
      await warnIfUnsatisfiable(plan.unsatisfiableKeys, traversal: plan.traversal)
      await warnIfReachabilityAcrossTree(plan.serializationKeys)
      let serializeStarted = CFAbsoluteTimeGetCurrent()
      let walked = FBAXTreeWalk.describeAllElements(
        fromTree: read.tree, keys: plan.serializationKeys, nestedFormat: plan.nestedFormat, pid: read.pid
      )
      let screen = FBAXTreeWalk.screenInfo(fromTree: read.tree)
      // The filter and the match both run before the interactable refinement, which is per-element guest
      // work there is no reason to spend on an element about to be dropped.
      let elements = try await refiningInteractable(
        options.narrowing(walked), screen: screen, options: options
      )
      // Measures serialize + refine, closed before response assembly.
      let serializeDuration = CFAbsoluteTimeGetCurrent() - serializeStarted
      // Coverage is a calculation over the serialized model, the same one every backend runs.
      // Remote-content discovery is accessibility-only, so `additional` stays absent here.
      let coverage: FBAccessibilityCoverage? =
        plan.collectFrameCoverage
        ? screen.flatMap {
          .measured(
            reported: elements, walked: walked, screenBounds: FBAccessibilityCoverage.bounds(of: $0),
            nested: plan.nestedFormat
          )
        } : nil
      // Judged on the reported elements — what the caller's `--filter` shows them.
      await warnIfMostElementsUnframed(FBAccessibilityFrameSummary(elements: elements))
      return FBAccessibilityElementsResponse(
        elements: .tree(elements),
        profilingData: plan.enableProfiling
          ? profile(
            for: read, elementCount: elements.nodeCount, serializeDuration: serializeDuration,
            traversal: plan.traversal
          ) : nil,
        coverage: coverage, modal: read.modal, automation: read.automation
      )
      .withProvenance(
        backend: backend.name,
        target: query.targetDescriptor,
        screen: screen,
        truncated: read.truncated
      )
      .withNarrowing(options.narrowingReport(walked: walked, reported: elements))
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
      let result = await refiningInteractable(of: element, ancestors: [], screen: screen, options: options)
      refined.append(result.element)
    }
    return refined
  }

  private func refiningInteractable(
    of element: FBAccessibilityDocumentElement,
    ancestors: [FBAXElementIdentity],
    screen: FBAccessibilityScreenInfo?,
    options: FBAccessibilityRequestOptions
  ) async -> (element: FBAccessibilityDocumentElement, identities: Set<FBAXElementIdentity>) {
    var element = element
    let identity = FBAXElementIdentity(element)
    let ancestryForChildren = ancestors + [identity]
    var descendantIdentities: Set<FBAXElementIdentity> = []
    if let children = element.children {
      var refined: [FBAccessibilityDocumentElement] = []
      refined.reserveCapacity(children.count)
      for child in children {
        let result = await refiningInteractable(
          of: child, ancestors: ancestryForChildren, screen: screen, options: options)
        refined.append(result.element)
        descendantIdentities.formUnion(result.identities)
      }
      element.children = refined
    }
    element = FBAXScreenBoundsClassifier.notingScreenClipping(element, screen: screen)
    if options.keys.contains(.occludedBy),
      case let .blocked(reasons)?? = element.interactable,
      let found = element.explainedBy
    {
      let foundIdentity = FBAXElementIdentity(found)
      let isRelative = ancestors.contains(foundIdentity) || descendantIdentities.contains(foundIdentity)
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
    }
    descendantIdentities.insert(identity)
    return (element, descendantIdentities)
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
