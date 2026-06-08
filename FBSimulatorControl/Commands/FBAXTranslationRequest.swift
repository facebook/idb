/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AccessibilityPlatformTranslation
import CoreSimulator
import FBControlCore
import Foundation

/// A single accessibility translation request. Carries the per-request token,
/// the resolved CoreSimulator device + translator, the profiling collector, and
/// the synchronous XPC timeout. Subclasses implement how the root element is
/// obtained (frontmost application vs. point) and how the response is serialized.
///
/// Created and driven entirely from Swift in this module (the dispatcher, the
/// element handle, and the facade), so it is a plain Swift class.
public class FBAXTranslationRequest {

  // Default timeout (in seconds) for synchronous accessibility XPC round-trips.
  // Healthy SpringBoard responses return well under 1s; 5s comfortably absorbs
  // scheduler jitter and slow-element edge cases while bounding the wedge condition
  // where the accessibility XPC service stalls and the caller would otherwise hang
  // indefinitely on a `DispatchGroup.wait`.
  private static let defaultRequestTimeoutSeconds: TimeInterval = 5.0

  public let token: String
  public var device: SimDevice?
  public var collector: FBAccessibilityProfilingCollector?
  public var logger: FBControlCoreLogger?
  public var frameCoverage: NSNumber?
  public var additionalFrameCoverage: NSNumber?
  public var translator: AXPTranslator?

  /// Per-request timeout (seconds) applied to each synchronous CoreSimulator
  /// accessibility XPC round-trip. `0` (or negative) is "wait nothing". There is
  /// no "wait forever" mode — a stalled XPC service never hangs the caller.
  public var requestTimeoutSeconds: TimeInterval

  public init() {
    self.token = UUID().uuidString
    self.requestTimeoutSeconds = Self.defaultRequestTimeoutSeconds
  }

  public func perform(withTranslator translator: AXPTranslator) -> AXPTranslationObject? {
    fatalError("\(type(of: self)).perform(withTranslator:) is abstract and should be overridden")
  }

  public func run(_ element: AXPMacPlatformElement, options: FBAccessibilityRequestOptions) throws -> FBAccessibilityElementsResponse {
    fatalError("\(type(of: self)).run(_:options:) is abstract and should be overridden")
  }

  public func cloneWithNewToken() -> FBAXTranslationRequest {
    fatalError("\(type(of: self)).cloneWithNewToken() is abstract and should be overridden")
  }

  // Builds the response, finalizing profiling timing — the Swift equivalent of the
  // old `FBAccessibilityElementsResponse (ResponseBuilder)` ObjC category.
  fileprivate func buildResponse(
    elements: Any,
    serializationStart: CFAbsoluteTime,
    frameCoverage: NSNumber?,
    additionalFrameCoverage: NSNumber?
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
}

// MARK: - Frontmost Application

public final class FBAXTranslationRequest_FrontmostApplication: FBAXTranslationRequest {

  public override func perform(withTranslator translator: AXPTranslator) -> AXPTranslationObject? {
    translator.frontmostApplication(withDisplayId: 0, bridgeDelegateToken: token)
  }

  public override func cloneWithNewToken() -> FBAXTranslationRequest {
    FBAXTranslationRequest_FrontmostApplication()
  }

  public override func run(_ element: AXPMacPlatformElement, options: FBAccessibilityRequestOptions) throws -> FBAccessibilityElementsResponse {
    // Screen bounds for coverage calculation and remote content fetching.
    let screenBounds = element.accessibilityFrame()

    // Coverage grid (populated during traversal) when requested.
    let grid: FBAccessibilityCoverageGrid? = options.collectFrameCoverage ? FBAccessibilityCoverageGrid(screenBounds: screenBounds) : nil

    // PIDs seen during traversal, for dedup during remote-content discovery.
    let seenPids = NSMutableSet()

    let serializationStart = CFAbsoluteTimeGetCurrent()

    // Serialize, passing the grid to be populated during traversal.
    let mainAppElements = FBSimulatorAccessibilitySerializer.recursiveDescription(
      fromElement: element,
      token: token,
      nestedFormat: options.nestedFormat,
      keys: options.keys ?? [],
      collector: collector,
      coverageGrid: grid,
      seenPids: seenPids,
      applicationElement: nil
    )
    // In nested format the root application element is the single returned element;
    // remote content is merged into its children.
    let applicationElement: NSMutableDictionary? = options.nestedFormat ? (mainAppElements.firstObject as? NSMutableDictionary) : nil

    // Base coverage after the main traversal.
    var frameCoverage: NSNumber?
    if let grid {
      let baseCoverage = grid.coverageRatio()
      if baseCoverage >= 0 {
        frameCoverage = NSNumber(value: Double(baseCoverage))
      }
    }

    // Remote content fetching (only when requested and a translator is present).
    guard let remoteOptions = options.remoteContentOptions, let translator else {
      return buildResponse(elements: mainAppElements, serializationStart: serializationStart, frameCoverage: frameCoverage, additionalFrameCoverage: nil)
    }

    let frontmostPid = element.translation?.pid ?? 0
    return processRemoteContent(
      mainAppElements: mainAppElements,
      applicationElement: applicationElement,
      screenBounds: screenBounds,
      frontmostPid: frontmostPid,
      seenPids: seenPids,
      coverageGrid: grid,
      frameCoverage: frameCoverage,
      serializationStart: serializationStart,
      options: options,
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
    seenPids: NSSet,
    coverageGrid: FBAccessibilityCoverageGrid?,
    options: FBAccessibilityRequestOptions,
    remoteOptions: FBAccessibilityRemoteContentOptions,
    translator: AXPTranslator
  ) -> [[String: Any]] {
    var discoveredElements: [[String: Any]] = []
    var discoveredFrames = Set<NSValue>()

    // Always include AXFrame for hit-tested elements (needed for nesting and coverage).
    var keysWithFrame = options.keys ?? []
    keysWithFrame.insert("AXFrame")

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
        if seenPids.contains(NSNumber(value: hitPid)) || hitPid <= 0 || hitPid == frontmostPid {
          x += stepSize
          continue
        }

        guard let rawHit = translator.macPlatformElement(fromTranslation: hitTranslation) else {
          x += stepSize
          continue
        }
        // Mirrors the unchecked typed cast used by the serializer and dispatcher so
        // message-responding test doubles (non-AXPMacPlatformElement subclasses) flow
        // through; identical to `as!` for the real elements returned in production.
        let hitElement = unsafeBitCast(rawHit as AnyObject, to: AXPMacPlatformElement.self)

        let hitFrame = hitElement.accessibilityFrame()
        let hitFrameValue = NSValue(rect: hitFrame)
        if discoveredFrames.contains(hitFrameValue) {
          x += stepSize
          continue
        }
        discoveredFrames.insert(hitFrameValue)

        coverageGrid?.markFilled(with: hitFrame)

        let elemDict = FBSimulatorAccessibilitySerializer.accessibilityDictionary(
          forElement: hitElement,
          token: token,
          keys: keysWithFrame,
          collector: collector,
          frontmostPid: frontmostPid,
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
    mainAppElements: NSMutableArray,
    applicationElement: NSMutableDictionary?,
    screenBounds: CGRect,
    frontmostPid: pid_t,
    seenPids: NSSet,
    coverageGrid: FBAccessibilityCoverageGrid?,
    frameCoverage: NSNumber?,
    serializationStart: CFAbsoluteTime,
    options: FBAccessibilityRequestOptions,
    remoteOptions: FBAccessibilityRemoteContentOptions,
    translator: AXPTranslator
  ) -> FBAccessibilityElementsResponse {
    let coverageBefore = coverageGrid?.coverageRatio() ?? 0

    let discoveredElements = discoverRemoteElements(
      screenBounds: screenBounds,
      frontmostPid: frontmostPid,
      seenPids: seenPids,
      coverageGrid: coverageGrid,
      options: options,
      remoteOptions: remoteOptions,
      translator: translator
    )

    var additionalFrameCoverage: NSNumber?
    if let coverageGrid, !discoveredElements.isEmpty {
      let additionalCoverage = coverageGrid.coverageRatio() - coverageBefore
      if additionalCoverage > 0 {
        additionalFrameCoverage = NSNumber(value: Double(additionalCoverage))
      }
    }

    if !discoveredElements.isEmpty {
      if let applicationElement {
        // Append to the Application element's children (nested format).
        let children =
          (applicationElement["children"] as? NSMutableArray)
          ?? {
            let array = NSMutableArray()
            applicationElement["children"] = array
            return array
          }()
        children.addObjects(from: discoveredElements)
      } else {
        // Append to the flat array.
        mainAppElements.addObjects(from: discoveredElements)
      }
    }

    return buildResponse(elements: mainAppElements, serializationStart: serializationStart, frameCoverage: frameCoverage, additionalFrameCoverage: additionalFrameCoverage)
  }
}

// MARK: - Point

public final class FBAXTranslationRequest_Point: FBAXTranslationRequest {

  public let point: CGPoint

  public init(point: CGPoint) {
    self.point = point
    super.init()
  }

  public override func perform(withTranslator translator: AXPTranslator) -> AXPTranslationObject? {
    translator.object(at: point, displayId: 0, bridgeDelegateToken: token)
  }

  public override func cloneWithNewToken() -> FBAXTranslationRequest {
    FBAXTranslationRequest_Point(point: point)
  }

  public override func run(_ element: AXPMacPlatformElement, options: FBAccessibilityRequestOptions) throws -> FBAccessibilityElementsResponse {
    let serializationStart = CFAbsoluteTimeGetCurrent()
    let elements = FBSimulatorAccessibilitySerializer.formattedDescription(
      ofElement: element,
      token: token,
      nestedFormat: options.nestedFormat,
      keys: options.keys ?? [],
      collector: collector,
      coverageGrid: nil
    )
    return buildResponse(elements: elements, serializationStart: serializationStart, frameCoverage: nil, additionalFrameCoverage: nil)
  }
}
