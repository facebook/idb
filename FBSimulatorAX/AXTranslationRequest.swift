/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

internal import AccessibilityPlatformTranslation
import CoreSimulator
import FBControlCore
import FBSimulatorControl
import Foundation

extension AXTranslationDisplay {
  var screen: AccessibilityScreenInfo? {
    let uniqueID: String? =
      switch interactionDisplay {
      case let .identified(value): value.uniqueID
      case .legacy: nil
      }
    let rotation: Int =
      switch geometry.rotation {
      case .upright: 0
      case .clockwise: 90
      case .upsideDown: 180
      case .counterclockwise: 270
      }
    return AccessibilityScreenInfo(
      width: bounds.width, height: bounds.height,
      display: AccessibilityDisplayInfo(uniqueID: uniqueID, scale: geometry.scale, rotation: rotation))
  }
}

/// Reference-typed accumulator for the process ids seen during a serialization
/// traversal. Populated as the main tree is serialized and shared with the
/// remote-content phase so processes already present in the main tree are
/// skipped during grid hit-testing.
final class SeenPIDs {
  private var pids: Set<pid_t> = []
  func insert(_ pid: pid_t) { pids.insert(pid) }
  func contains(_ pid: pid_t) -> Bool { pids.contains(pid) }
}

/// A single accessibility translation request. `kind` selects how the root element is obtained and
/// how the response is serialized.
final class AXTranslationRequest {

  /// What the request resolves and how it serializes.
  enum Kind {
    /// The frontmost application's element tree, with frame-coverage calculation
    /// and remote (separate-process) content discovery.
    case frontmostApplication
    /// The single element at a screen point.
    case point(CGPoint)
    /// A specific application's element tree, anchored by process identifier — no hit-test and no
    /// frontmost resolution. Serialized like `frontmostApplication` (full tree + coverage).
    case applicationForPid(pid_t)
  }

  // Default timeout (in seconds) for synchronous accessibility XPC round-trips.
  // Healthy responses return well under 1s; 5s bounds a stalled accessibility XPC
  // service so the caller never hangs on `DispatchGroup.wait`.
  private static let defaultRequestTimeoutSeconds: TimeInterval = 5.0

  let kind: Kind
  let display: AXTranslationDisplay?
  /// The client every translator request for this read carries, resolved by the caller.
  let clientType: AXClientType
  let token: String
  /// Carries this read's translator requests to the simulator.
  var transport: (any AXTranslationTransport)?
  /// Owned from construction: the dispatcher records acquisition timings before the caller reaches
  /// `serialize`.
  var collector: AccessibilityProfilingCollector
  var translator: AXPTranslator?

  /// Per-request timeout (seconds) applied to each synchronous CoreSimulator
  /// accessibility XPC round-trip. `0` (or negative) is "wait nothing". There is
  /// no "wait forever" mode — a stalled XPC service never hangs the caller.
  var requestTimeoutSeconds: TimeInterval

  init(kind: Kind, display: AXTranslationDisplay? = nil, clientType: AXClientType) {
    self.kind = kind
    self.display = display
    self.clientType = clientType
    self.token = UUID().uuidString
    self.requestTimeoutSeconds = Self.defaultRequestTimeoutSeconds
    self.collector = AccessibilityProfilingCollector()
  }

  /// A fresh request of the same kind with a new token, used to retry after
  /// SpringBoard remediation.
  ///
  /// The collector carries over so the profile spans the failed attempt the caller also waited through.
  func cloneWithNewToken() -> AXTranslationRequest {
    let clone = AXTranslationRequest(kind: kind, display: display, clientType: clientType)
    clone.collector = collector
    return clone
  }

  /// Resolves the root translation object for this request's kind.
  func perform(withTranslator translator: AXPTranslator) throws -> AXPTranslationObject? {
    switch kind {
    case .frontmostApplication:
      return translator.frontmostApplication(withDisplayId: displayID, bridgeDelegateToken: token)
    case .point(let point):
      return try translation(at: point, translator: translator)
    case .applicationForPid(let pid):
      return translator.translationApplicationObject(forPid: pid)
    }
  }

  /// Serializes the resolved element. The frontmost path adds frame coverage and remote content; the
  /// point path is a single element. `isMarkerMatch` forces single-element serialization: a marker
  /// match descends from the frontmost tree, so its request's `kind` is still `.frontmostApplication`.
  func run(
    _ element: AXPlatformElement,
    options: AccessibilityRequestOptions,
    isMarkerMatch: Bool = false
  ) throws -> AccessibilityElementsResponse {
    guard !isMarkerMatch else {
      return runNamedElement(element, options: options)
    }
    switch kind {
    case .point:
      return runNamedElement(element, options: options)
    case .frontmostApplication, .applicationForPid:
      return try runFrontmostApplication(element, options: options)
    }
  }

  // MARK: - A single named element

  /// Serializes the one element a caller named — by point, or by a marker match. The element itself is
  /// always reported; only its descendants are subject to the filter.
  private func runNamedElement(_ element: AXPlatformElement, options: AccessibilityRequestOptions) -> AccessibilityElementsResponse {
    let walkStart = CFAbsoluteTimeGetCurrent()
    collector.markWalkStart()
    let serialization = AXSerialization(options)
    let snapshot = AXElementSnapshot.read(
      element, plan: serialization.readPlan(depth: serialization.nested ? .unlimited : .limited(0)), token: token,
      mode: options.translatorReads)
    var elements = AXNodeSerializer.formattedDescription(ofSnapshot: snapshot, serialization: serialization, collector: collector)
    if let children = elements.children {
      elements.children = options.filter.apply(to: children, screen: nil)
    }
    // Without a display snapshot, marker callers can recover legacy bounds from the root.
    return buildResponse(elements: .single(elements), walkStart: walkStart, coverage: nil, screen: display?.screen, options: options)
  }

  // MARK: - Frontmost Application

  private func runFrontmostApplication(_ element: AXPlatformElement, options: AccessibilityRequestOptions) throws -> AccessibilityElementsResponse {
    let walkStart = CFAbsoluteTimeGetCurrent()
    collector.markWalkStart()

    let serialization = AXSerialization(options)
    let snapshot = AXElementSnapshot.read(
      element, plan: serialization.readPlan(depth: .unlimited), token: token, mode: options.translatorReads)
    let screen = AXReadScreen(display: display, rootFrame: snapshot.frame)
    let seenPids = SeenPIDs()

    let tree = TranslatedTree(
      description: AccessibilityTreeDescription(
        walked: AXNodeSerializer.recursiveDescription(
          fromSnapshot: snapshot, serialization: serialization, collector: collector, seenPids: seenPids),
        options: options, screenBounds: screen.bounds),
      pid: snapshot.pid, seenPids: seenPids)

    // The grid stays live: remote-content discovery reads it to skip covered points and marks its hits
    // into it.
    let grid: AccessibilityCoverageGrid? =
      options.collectFrameCoverage ? AccessibilityCoverageGrid(screenBounds: screen.bounds) : nil
    grid?.markFilled(withElements: tree.description.reported)

    guard let remoteOptions = options.remoteContentOptions, let translator else {
      return buildResponse(
        elements: .tree(tree.description.reported),
        walkStart: walkStart,
        coverage: tree.description.coverage(),
        screen: screen.info,
        options: options,
        narrowing: tree.description.narrowingReport()
      )
    }

    return try processRemoteContent(
      tree: tree,
      screen: screen,
      grid: grid,
      plan: AXRemoteContentPlan(remoteOptions, screenBounds: screen.bounds),
      options: options,
      walkStart: walkStart,
      translator: translator
    )
  }

  /// The frontmost application's described tree, the application's pid, and every pid seen on the way.
  private struct TranslatedTree {
    let description: AccessibilityTreeDescription
    let pid: pid_t
    let seenPids: SeenPIDs
  }

  // MARK: - Remote content

  private func discoverRemoteElements(
    beyond tree: TranslatedTree,
    grid: AccessibilityCoverageGrid?,
    plan: AXRemoteContentPlan,
    keys: Set<AXKeys>,
    reads: AXTranslatorReads,
    translator: AXPTranslator
  ) throws -> [AccessibilityDocumentElement] {
    var discoveredElements: [AccessibilityDocumentElement] = []
    var discoveredFrames = Set<String>()

    // Always include AXFrame for hit-tested elements (needed for nesting and coverage).
    var keysWithFrame = keys
    keysWithFrame.insert(.frame)

    var visited: UInt = 0
    for point in plan.points {
      if plan.isExhausted(afterVisiting: visited) {
        break
      }
      if let grid, grid.isFilled(at: point) {
        continue
      }
      visited += 1

      // A caller's region can reach past the routed display, where no point translates.
      let translated: AXPTranslationObject?
      do {
        translated = try translation(at: point, translator: translator)
      } catch SimulatorDisplayInteractionError.invalidPoint {
        translated = nil
      }
      guard let hitTranslation = translated else {
        continue
      }
      hitTranslation.bridgeDelegateToken = token
      let hitPid = hitTranslation.pid
      if tree.seenPids.contains(hitPid) || hitPid <= 0 || hitPid == tree.pid {
        continue
      }
      guard let hitElement = translator.macPlatformElement(fromTranslation: hitTranslation) as? AXPlatformElement else {
        continue
      }

      // One read serves both the duplicate check and the serialization.
      let hit = AXElementSnapshot.read(
        hitElement, plan: AXReadPlan(keys: keysWithFrame, depth: .limited(0)), token: token, mode: reads)
      let hitFrame = hit.frame
      let hitFrameKey = "\(hitFrame.origin.x),\(hitFrame.origin.y),\(hitFrame.size.width),\(hitFrame.size.height)"
      if discoveredFrames.contains(hitFrameKey) {
        continue
      }
      discoveredFrames.insert(hitFrameKey)
      grid?.markFilled(with: hitFrame)

      discoveredElements.append(
        AXNodeSerializer.decoratedElement(
          forSnapshot: hit, keys: keysWithFrame, collector: collector, seenPids: nil, isRemote: true))
    }
    return discoveredElements
  }

  private func processRemoteContent(
    tree: TranslatedTree,
    screen: AXReadScreen,
    grid: AccessibilityCoverageGrid?,
    plan: AXRemoteContentPlan,
    options: AccessibilityRequestOptions,
    walkStart: CFAbsoluteTime,
    translator: AXPTranslator
  ) throws -> AccessibilityElementsResponse {
    let coverageBefore = grid?.coverageRatio() ?? 0

    let discoveredElements = try discoverRemoteElements(
      beyond: tree, grid: grid, plan: plan, keys: options.serializationKeys, reads: options.translatorReads,
      translator: translator)

    var additionalFrameCoverage: Double?
    if let grid, !discoveredElements.isEmpty {
      let additionalCoverage = grid.coverageRatio() - coverageBefore
      if additionalCoverage > 0 {
        additionalFrameCoverage = Double(additionalCoverage)
      }
    }

    // Discovered elements honour the same filter and match as the main tree. `additionalFrameCoverage`
    // is measured before narrowing: it reports what hit-testing found that the tree did not expose.
    let keptDiscovered = AccessibilityElementRetention.narrowing(
      discoveredElements, filter: options.filter, match: options.match, screen: screen.bounds
    )
    var elements = tree.description.reported
    if !keptDiscovered.isEmpty {
      if options.nestedFormat, var applicationElement = elements.first {
        applicationElement.children = (applicationElement.children ?? []) + keptDiscovered
        elements[0] = applicationElement
      } else {
        elements.append(contentsOf: keptDiscovered)
      }
    }

    return buildResponse(
      elements: .tree(elements),
      walkStart: walkStart,
      coverage: tree.description.coverage(additional: additionalFrameCoverage),
      screen: screen.info,
      options: options,
      narrowing: tree.description.narrowingReport(reporting: elements, discovered: discoveredElements)
    )
  }

  /// The display the translator resolves against; 0 is the main display, which needs no name.
  private var displayID: UInt32 {
    display?.accessibilityID ?? 0
  }

  private func translation(at point: CGPoint, translator: AXPTranslator) throws -> AXPTranslationObject? {
    let unrotated = try display?.geometry.unrotatedPoint(from: point) ?? point
    return translator.object(at: unrotated, displayId: displayID, bridgeDelegateToken: token)
  }

  // MARK: - Helpers

  // `truncated` is always false: this path walks the live tree with no depth or node bound.
  private func buildResponse(
    elements: AccessibilityElementPayload,
    walkStart: CFAbsoluteTime,
    coverage: AccessibilityCoverage?,
    screen: AccessibilityScreenInfo?,
    options: AccessibilityRequestOptions,
    narrowing: AccessibilityNarrowing? = nil
  ) -> AccessibilityElementsResponse {
    let walkDuration = CFAbsoluteTimeGetCurrent() - walkStart
    // Collected always (cheap) and kept as metrics on every read; reported as a profile only when
    // profiling was requested.
    let profile = collector.finalize(withWalkDuration: walkDuration)
    let metrics = transport.map {
      AccessibilityTranslatorReadMetrics(
        elementCount: profile.elementCount,
        roundTrips: profile.xpcCallCount,
        readDuration: profile.readDuration,
        totalDuration: profile.totalDuration,
        translatorReads: options.translatorReads,
        transport: $0.kind)
    }
    return AccessibilityElementsResponse(
      elements: elements,
      profilingData: options.enableProfiling ? .translator(profile) : nil,
      coverage: coverage,
      truncated: false,
      screen: screen,
      narrowing: narrowing,
      translatorMetrics: metrics
    )
  }
}
