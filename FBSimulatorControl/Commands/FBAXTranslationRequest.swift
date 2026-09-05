/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@_implementationOnly import AccessibilityPlatformTranslation
import CoreSimulator
import FBControlCore
import Foundation

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
final class FBAXTranslationRequest {

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
  let token: String
  var device: SimDevice?
  /// Owned from construction: the dispatcher records acquisition timings before the caller reaches
  /// `serialize`.
  var collector: FBAccessibilityProfilingCollector
  var logger: FBControlCoreLogger?
  var translator: AXPTranslator?

  /// Per-request timeout (seconds) applied to each synchronous CoreSimulator
  /// accessibility XPC round-trip. `0` (or negative) is "wait nothing". There is
  /// no "wait forever" mode — a stalled XPC service never hangs the caller.
  var requestTimeoutSeconds: TimeInterval

  init(kind: Kind) {
    self.kind = kind
    self.token = UUID().uuidString
    self.requestTimeoutSeconds = Self.defaultRequestTimeoutSeconds
    self.collector = FBAccessibilityProfilingCollector()
  }

  /// A fresh request of the same kind with a new token, used to retry after
  /// SpringBoard remediation.
  ///
  /// The collector carries over so the profile spans the failed attempt the caller also waited through.
  func cloneWithNewToken() -> FBAXTranslationRequest {
    let clone = FBAXTranslationRequest(kind: kind)
    clone.collector = collector
    return clone
  }

  /// Resolves the root translation object for this request's kind.
  func perform(withTranslator translator: AXPTranslator) -> AXPTranslationObject? {
    switch kind {
    case .frontmostApplication:
      return translator.frontmostApplication(withDisplayId: 0, bridgeDelegateToken: token)
    case .point(let point):
      return translator.object(at: point, displayId: 0, bridgeDelegateToken: token)
    case .applicationForPid(let pid):
      return translator.translationApplicationObject(forPid: pid)
    }
  }

  /// Serializes the resolved element. The frontmost path adds frame coverage and remote content; the
  /// point path is a single element. `isMarkerMatch` forces single-element serialization: a marker
  /// match descends from the frontmost tree, so its request's `kind` is still `.frontmostApplication`.
  func run(
    _ element: FBAXPlatformElement,
    options: FBAccessibilityRequestOptions,
    isMarkerMatch: Bool = false
  ) throws -> FBAccessibilityElementsResponse {
    guard !isMarkerMatch else {
      return runNamedElement(element, options: options)
    }
    switch kind {
    case .point:
      return runNamedElement(element, options: options)
    case .frontmostApplication, .applicationForPid:
      return runFrontmostApplication(element, options: options)
    }
  }

  // MARK: - A single named element

  /// Serializes the one element a caller named — by point, or by a marker match. The element itself is
  /// always reported; only its descendants are subject to the filter.
  private func runNamedElement(_ element: FBAXPlatformElement, options: FBAccessibilityRequestOptions) -> FBAccessibilityElementsResponse {
    let walkStart = CFAbsoluteTimeGetCurrent()
    collector.markWalkStart()
    var elements = FBAXNodeSerializer.formattedDescription(
      ofElement: element,
      token: token,
      nestedFormat: options.nestedFormat,
      keys: Self.serializerKeys(options),
      collector: collector
    )
    if let children = elements.children {
      elements.children = options.filter.apply(to: children)
    }
    // A named element carries no screen info of its own; a marker match's bounds come from the root it
    // descended from, stamped by the backend on the way out.
    return buildResponse(
      elements: .single(elements), walkStart: walkStart, coverage: nil, screen: nil,
      reportProfile: options.enableProfiling
    )
  }

  // MARK: - Frontmost Application

  private func runFrontmostApplication(_ element: FBAXPlatformElement, options: FBAccessibilityRequestOptions) -> FBAccessibilityElementsResponse {
    // Marked before the screen-bounds fetch so that fetch is inside the measured walk.
    let walkStart = CFAbsoluteTimeGetCurrent()
    collector.markWalkStart()

    let screenBounds = element.axFrame()
    let seenPids = SeenPIDs()

    let keys = Self.serializerKeys(options)

    let walked = FBAXNodeSerializer.recursiveDescription(
      fromElement: element,
      token: token,
      nestedFormat: options.nestedFormat,
      keys: keys,
      collector: collector,
      seenPids: seenPids
    )
    let mainAppElements = options.narrowing(walked)

    // The grid stays live: remote-content discovery reads it to skip covered points and marks its hits
    // into it.
    let grid: FBAccessibilityCoverageGrid? =
      options.collectFrameCoverage ? FBAccessibilityCoverageGrid(screenBounds: screenBounds) : nil
    grid?.markFilled(withElements: mainAppElements)

    guard let remoteOptions = options.remoteContentOptions, let translator else {
      return buildResponse(
        elements: .tree(mainAppElements),
        walkStart: walkStart,
        coverage: options.collectFrameCoverage
          ? .measured(
            reported: mainAppElements, walked: walked, screenBounds: screenBounds,
            nested: options.nestedFormat
          ) : nil,
        screen: Self.screenInfo(fromBounds: screenBounds),
        reportProfile: options.enableProfiling,
        narrowing: options.narrowingReport(walked: walked, reported: mainAppElements)
      )
    }

    let frontmostPid = element.axTranslationPid
    return processRemoteContent(
      mainAppElements: mainAppElements,
      nestedFormat: options.nestedFormat,
      filter: options.filter,
      match: options.match,
      screenBounds: screenBounds,
      frontmostPid: frontmostPid,
      seenPids: seenPids,
      coverageGrid: grid,
      walkedElements: walked,
      collectFrameCoverage: options.collectFrameCoverage,
      reportProfile: options.enableProfiling,
      walkStart: walkStart,
      keys: keys,
      remoteOptions: remoteOptions,
      translator: translator
    )
  }

  // MARK: Remote content

  private func discoverRemoteElements(
    screenBounds: CGRect,
    frontmostPid: pid_t,
    seenPids: SeenPIDs,
    coverageGrid: FBAccessibilityCoverageGrid?,
    keys: Set<FBAXKeys>,
    remoteOptions: FBAccessibilityRemoteContentOptions,
    translator: AXPTranslator
  ) -> [FBAccessibilityDocumentElement] {
    var discoveredElements: [FBAccessibilityDocumentElement] = []
    var discoveredFrames = Set<String>()

    // Always include AXFrame for hit-tested elements (needed for nesting and coverage).
    var keysWithFrame = keys
    keysWithFrame.insert(.frame)

    let stepSize = remoteOptions.gridStepSize > 0 ? remoteOptions.gridStepSize : 50.0
    let region = remoteOptions.region.isNull ? screenBounds : remoteOptions.region
    let maxPoints = remoteOptions.maxPoints
    var pointCount: UInt = 0

    var y = stepSize
    while y < region.size.height - stepSize {
      var x = stepSize
      while x < region.size.width - stepSize {
        if maxPoints > 0, pointCount >= maxPoints {
          break
        }

        let point = CGPoint(x: region.origin.x + x, y: region.origin.y + y)

        if let coverageGrid, coverageGrid.isFilled(at: point) {
          x += stepSize
          continue
        }

        pointCount += 1

        guard let hitTranslation = translator.object(at: point, displayId: 0, bridgeDelegateToken: token) else {
          x += stepSize
          continue
        }
        hitTranslation.bridgeDelegateToken = token
        let hitPid = hitTranslation.pid

        if seenPids.contains(hitPid) || hitPid <= 0 || hitPid == frontmostPid {
          x += stepSize
          continue
        }

        guard let hitElement = translator.macPlatformElement(fromTranslation: hitTranslation) as? FBAXPlatformElement else {
          x += stepSize
          continue
        }

        let hitFrame = hitElement.axFrame()
        let hitFrameKey = "\(hitFrame.origin.x),\(hitFrame.origin.y),\(hitFrame.size.width),\(hitFrame.size.height)"
        if discoveredFrames.contains(hitFrameKey) {
          x += stepSize
          continue
        }
        discoveredFrames.insert(hitFrameKey)

        coverageGrid?.markFilled(with: hitFrame)

        let discovered = FBAXNodeSerializer.decoratedElement(
          forElement: hitElement,
          token: token,
          keys: keysWithFrame,
          collector: collector,
          seenPids: nil,
          isRemote: true
        )
        discoveredElements.append(discovered)

        x += stepSize
      }
      if maxPoints > 0, pointCount >= maxPoints {
        break
      }
      y += stepSize
    }

    return discoveredElements
  }

  private func processRemoteContent(
    mainAppElements: [FBAccessibilityDocumentElement],
    nestedFormat: Bool,
    filter: FBAccessibilityElementFilter,
    match: FBAccessibilityMatch?,
    screenBounds: CGRect,
    frontmostPid: pid_t,
    seenPids: SeenPIDs,
    coverageGrid: FBAccessibilityCoverageGrid?,
    walkedElements: [FBAccessibilityDocumentElement],
    collectFrameCoverage: Bool,
    reportProfile: Bool,
    walkStart: CFAbsoluteTime,
    keys: Set<FBAXKeys>,
    remoteOptions: FBAccessibilityRemoteContentOptions,
    translator: AXPTranslator
  ) -> FBAccessibilityElementsResponse {
    let coverageBefore = coverageGrid?.coverageRatio() ?? 0

    let discoveredElements = discoverRemoteElements(
      screenBounds: screenBounds,
      frontmostPid: frontmostPid,
      seenPids: seenPids,
      coverageGrid: coverageGrid,
      keys: keys,
      remoteOptions: remoteOptions,
      translator: translator
    )

    var additionalFrameCoverage: Double?
    if let coverageGrid, !discoveredElements.isEmpty {
      let additionalCoverage = coverageGrid.coverageRatio() - coverageBefore
      if additionalCoverage > 0 {
        additionalFrameCoverage = Double(additionalCoverage)
      }
    }

    // Discovered elements honour the same filter and match as the main tree. `additionalFrameCoverage`
    // is measured before narrowing: it reports what hit-testing found that the tree did not expose.
    let keptDiscovered = FBAccessibilityElementRetention.narrowing(
      discoveredElements, filter: filter, match: match
    )
    var elements = mainAppElements
    if !keptDiscovered.isEmpty {
      if nestedFormat, var applicationElement = elements.first {
        applicationElement.children = (applicationElement.children ?? []) + keptDiscovered
        elements[0] = applicationElement
      } else {
        elements.append(contentsOf: keptDiscovered)
      }
    }

    return buildResponse(
      elements: .tree(elements),
      walkStart: walkStart,
      coverage: collectFrameCoverage
        ? .measured(
          reported: mainAppElements, walked: walkedElements, screenBounds: screenBounds,
          nested: nestedFormat, additional: additionalFrameCoverage
        ) : nil,
      screen: Self.screenInfo(fromBounds: screenBounds),
      reportProfile: reportProfile,
      // Discovered elements count as walked too, or a read could report more matched than walked.
      narrowing: FBAccessibilityNarrowing(
        filter: filter, match: match,
        walked: walkedElements, discovered: discoveredElements, reported: elements)
    )
  }

  // MARK: - Helpers

  // `truncated` is always false: this path walks the live tree with no depth or node bound.
  private func buildResponse(
    elements: FBAccessibilityElementPayload,
    walkStart: CFAbsoluteTime,
    coverage: FBAccessibilityCoverage?,
    screen: FBAccessibilityScreenInfo?,
    reportProfile: Bool,
    narrowing: FBAccessibilityNarrowing? = nil
  ) -> FBAccessibilityElementsResponse {
    let walkDuration = CFAbsoluteTimeGetCurrent() - walkStart
    // Collected always (cheap); reported only when profiling was requested.
    let profilingData = reportProfile ? collector.finalize(withWalkDuration: walkDuration) : nil
    return FBAccessibilityElementsResponse(
      elements: elements,
      profilingData: profilingData.map { .translator($0) },
      coverage: coverage,
      truncated: false,
      screen: screen,
      narrowing: narrowing
    )
  }

  /// The screen bounds a read's frames are relative to; `nil` for a degenerate rectangle, so an unknown
  /// screen is reported as unknown rather than zero-sized.
  static func screenInfo(fromBounds bounds: CGRect) -> FBAccessibilityScreenInfo? {
    guard bounds.width > 0, bounds.height > 0 else {
      return nil
    }
    return FBAccessibilityScreenInfo(width: Double(bounds.width), height: Double(bounds.height))
  }

  private static func serializerKeys(_ options: FBAccessibilityRequestOptions) -> Set<FBAXKeys> {
    options.serializationKeys
  }
}
