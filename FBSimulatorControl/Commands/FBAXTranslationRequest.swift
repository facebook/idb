/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@_implementationOnly import AccessibilityPlatformTranslation
@_implementationOnly import CoreSimulator
import FBControlCore
import Foundation

/// A single accessibility translation request. Carries the per-request token,
/// the resolved CoreSimulator device + translator, the profiling collector, and
/// the synchronous XPC timeout. The `kind` selects how the root element is
/// obtained (the frontmost application or the element at a point) and how the
/// response is serialized.
///
/// Created and driven entirely from Swift in this module (the dispatcher, the
/// element handle, and the facade), so it is a plain Swift class.
final class FBAXTranslationRequest {

  /// What the request resolves and how it serializes.
  enum Kind {
    /// The frontmost application's element tree, with frame-coverage calculation
    /// and remote (separate-process) content discovery.
    case frontmostApplication
    /// The single element at a screen point.
    case point(CGPoint)
  }

  // Default timeout (in seconds) for synchronous accessibility XPC round-trips.
  // Healthy SpringBoard responses return well under 1s; 5s comfortably absorbs
  // scheduler jitter and slow-element edge cases while bounding the wedge condition
  // where the accessibility XPC service stalls and the caller would otherwise hang
  // indefinitely on a `DispatchGroup.wait`.
  private static let defaultRequestTimeoutSeconds: TimeInterval = 5.0

  let kind: Kind
  let token: String
  var device: SimDevice?
  var collector: FBAccessibilityProfilingCollector?
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
  }

  /// A fresh request of the same kind with a new token, used to retry after
  /// SpringBoard remediation.
  func cloneWithNewToken() -> FBAXTranslationRequest {
    FBAXTranslationRequest(kind: kind)
  }

  /// Resolves the root translation object for this request's kind.
  func perform(withTranslator translator: AXPTranslator) -> AXPTranslationObject? {
    switch kind {
    case .frontmostApplication:
      return translator.frontmostApplication(withDisplayId: 0, bridgeDelegateToken: token)
    case .point(let point):
      return translator.object(at: point, displayId: 0, bridgeDelegateToken: token)
    }
  }

  /// Serializes the resolved element into a response. The frontmost-application
  /// path additionally computes frame coverage and merges remote (separate-process)
  /// content; the point path is a single-element description.
  func run(_ element: FBAXPlatformElement, options: FBAccessibilityRequestOptions) throws -> FBAccessibilityElementsResponse {
    switch kind {
    case .point:
      return runPoint(element, options: options)
    case .frontmostApplication:
      return runFrontmostApplication(element, options: options)
    }
  }

  // MARK: - Point

  private func runPoint(_ element: FBAXPlatformElement, options: FBAccessibilityRequestOptions) -> FBAccessibilityElementsResponse {
    let serializationStart = CFAbsoluteTimeGetCurrent()
    let elements = FBSimulatorAccessibilitySerializer.formattedDescription(
      ofElement: element,
      token: token,
      nestedFormat: options.nestedFormat,
      keys: Self.serializerKeys(options),
      collector: collector,
      coverageGrid: nil,
      maxDepth: options.maxDepth
    )
    return buildResponse(elements: elements, serializationStart: serializationStart, frameCoverage: nil, additionalFrameCoverage: nil)
  }

  // MARK: - Frontmost Application

  private func runFrontmostApplication(_ element: FBAXPlatformElement, options: FBAccessibilityRequestOptions) -> FBAccessibilityElementsResponse {
    // Screen bounds for coverage calculation and remote content fetching.
    let screenBounds = element.axFrame()

    // Coverage grid (populated during traversal) when requested.
    let grid: FBAccessibilityCoverageGrid? = options.collectFrameCoverage ? FBAccessibilityCoverageGrid(screenBounds: screenBounds) : nil

    // PIDs seen during traversal, for dedup during remote-content discovery.
    let seenPids = SeenPIDs()

    let keys = Self.serializerKeys(options)
    let serializationStart = CFAbsoluteTimeGetCurrent()

    // Serialize, passing the grid to be populated during traversal.
    let mainAppElements = FBSimulatorAccessibilitySerializer.recursiveDescription(
      fromElement: element,
      token: token,
      nestedFormat: options.nestedFormat,
      keys: keys,
      collector: collector,
      coverageGrid: grid,
      seenPids: seenPids,
      maxDepth: options.maxDepth
    )

    // Base coverage after the main traversal.
    var frameCoverage: Double?
    if let grid {
      let baseCoverage = grid.coverageRatio()
      if baseCoverage >= 0 {
        frameCoverage = Double(baseCoverage)
      }
    }

    // Remote content fetching (only when requested and a translator is present).
    guard let remoteOptions = options.remoteContentOptions, let translator else {
      return buildResponse(elements: mainAppElements, serializationStart: serializationStart, frameCoverage: frameCoverage, additionalFrameCoverage: nil)
    }

    let frontmostPid = element.axTranslationPid
    return processRemoteContent(
      mainAppElements: mainAppElements,
      nestedFormat: options.nestedFormat,
      screenBounds: screenBounds,
      frontmostPid: frontmostPid,
      seenPids: seenPids,
      coverageGrid: grid,
      frameCoverage: frameCoverage,
      serializationStart: serializationStart,
      keys: keys,
      remoteOptions: remoteOptions,
      translator: translator
    )
  }

  // MARK: Remote content

  // Discover remote elements via grid-based hit-testing, skipping PIDs already
  // seen in the main traversal. Returns the discovered element dictionaries.
  private func discoverRemoteElements(
    screenBounds: CGRect,
    frontmostPid: pid_t,
    seenPids: SeenPIDs,
    coverageGrid: FBAccessibilityCoverageGrid?,
    keys: Set<FBAXKeys>,
    remoteOptions: FBAccessibilityRemoteContentOptions,
    translator: AXPTranslator
  ) -> [[String: Any]] {
    var discoveredElements: [[String: Any]] = []
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

        // Skip points already covered by native accessibility elements.
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

        // Skip PIDs already seen in the main traversal, and the frontmost app itself.
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

        let elemDict = FBSimulatorAccessibilitySerializer.accessibilityDictionary(
          forElement: hitElement,
          token: token,
          keys: keysWithFrame,
          collector: collector,
          coverageGrid: nil, // already marked above
          seenPids: nil, // already filtered
          discoveryMethod: "point_grid"
        )
        discoveredElements.append(elemDict)

        x += stepSize
      }
      if maxPoints > 0, pointCount >= maxPoints {
        break
      }
      y += stepSize
    }

    return discoveredElements
  }

  // Process remote-content discovery and merge with the main elements.
  private func processRemoteContent(
    mainAppElements: [[String: Any]],
    nestedFormat: Bool,
    screenBounds: CGRect,
    frontmostPid: pid_t,
    seenPids: SeenPIDs,
    coverageGrid: FBAccessibilityCoverageGrid?,
    frameCoverage: Double?,
    serializationStart: CFAbsoluteTime,
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

    var elements = mainAppElements
    if !discoveredElements.isEmpty {
      if nestedFormat, var applicationElement = elements.first {
        // Append to the root Application element's children (nested format).
        var children = applicationElement["children"] as? [[String: Any]] ?? []
        children.append(contentsOf: discoveredElements)
        applicationElement["children"] = children
        elements[0] = applicationElement
      } else {
        // Append to the flat array.
        elements.append(contentsOf: discoveredElements)
      }
    }

    return buildResponse(elements: elements, serializationStart: serializationStart, frameCoverage: frameCoverage, additionalFrameCoverage: additionalFrameCoverage)
  }

  // MARK: - Helpers

  // Builds the response, finalizing profiling timing — the Swift equivalent of the
  // old `FBAccessibilityElementsResponse (ResponseBuilder)` ObjC category.
  private func buildResponse(
    elements: Any,
    serializationStart: CFAbsoluteTime,
    frameCoverage: Double?,
    additionalFrameCoverage: Double?
  ) -> FBAccessibilityElementsResponse {
    let serializationDuration = CFAbsoluteTimeGetCurrent() - serializationStart
    let profilingData = collector?.finalize(withSerializationDuration: serializationDuration)
    return FBAccessibilityElementsResponse(
      elements: elements,
      profilingData: profilingData,
      frameCoverage: frameCoverage,
      additionalFrameCoverage: additionalFrameCoverage
    )
  }

  // The keys to serialize, or an empty set when none were requested.
  private static func serializerKeys(_ options: FBAccessibilityRequestOptions) -> Set<FBAXKeys> {
    options.keys ?? []
  }
}
