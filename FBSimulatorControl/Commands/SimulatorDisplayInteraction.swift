/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public enum SimulatorDisplayInteractionError: Error, LocalizedError {
  case unsupportedCapability(String)
  case inactiveDisplay(String)
  case missingMapping(String)
  case invalidPoint(CGPoint, bounds: CGSize)
  case nonFinitePoint(CGPoint)

  public var errorDescription: String? {
    switch self {
    case let .unsupportedCapability(capability): "Simulator does not support \(capability)"
    case let .inactiveDisplay(id): "Display \(id) is not the active integrated display"
    case let .missingMapping(id): "Display \(id) has no unique accessibility and touchscreen mapping"
    case let .invalidPoint(point, bounds):
      "Touch point (\(point.x), \(point.y)) \(Self.invalidity(of: point)) the display's point bounds (\(bounds.width) x \(bounds.height))"
    case let .nonFinitePoint(point):
      "Touch point (\(point.x), \(point.y)) is not a real position (\(Self.nonFiniteAxes(of: point).joined(separator: ", ")))"
    }
  }

  private static func invalidity(of point: CGPoint) -> String {
    let nonFinite = nonFiniteAxes(of: point)
    if nonFinite.isEmpty { return "is outside" }
    return "is not a real position (\(nonFinite.joined(separator: ", "))) within"
  }

  private static func nonFiniteAxes(of point: CGPoint) -> [String] {
    [("x", point.x), ("y", point.y)].compactMap { axis, value in
      value.isNaN ? "\(axis) is NaN" : value.isInfinite ? "\(axis) is infinite" : nil
    }
  }
}

/// An immutable mapping for one observed display configuration. Numeric IDs belong to separate namespaces.
/// Revalidate before using saved coordinates.
public struct SimulatorDisplayInteractionContext: Equatable, Sendable {
  public let display: SimulatorDisplay
  public let accessibilityDisplayID: UInt32
  public let digitizerTarget: UInt32
  /// The `SimulatorDisplayConfiguration.generation` the mapping was resolved in.
  public let generation: UInt64

  /// Display-relative dimensions in points, after interface rotation.
  public var pointSize: CGSize {
    CGSize(width: display.size.width / display.scale, height: display.size.height / display.scale)
  }

  /// Converts display-relative points to unrotated, normalized digitizer coordinates.
  public func digitizerPoint(from point: CGPoint) throws -> CGPoint {
    let size = pointSize
    guard point.x.isFinite, point.y.isFinite,
      point.x >= 0, point.y >= 0, point.x <= size.width, point.y <= size.height
    else { throw SimulatorDisplayInteractionError.invalidPoint(point, bounds: size) }
    let x = point.x / size.width
    let y = point.y / size.height
    switch display.rotation {
    case .upright: return CGPoint(x: x, y: y)
    case .clockwise: return CGPoint(x: y, y: 1 - x)
    case .upsideDown: return CGPoint(x: 1 - x, y: 1 - y)
    case .counterclockwise: return CGPoint(x: 1 - y, y: x)
    }
  }
}

struct SimulatorAccessibilityDisplay: Decodable, Equatable, Sendable {
  let uniqueID: String
  let displayID: UInt32
}

/// What the guest advertises it can scope to a named display, beyond reporting its displays.
struct AXBridgeDisplayCapabilities: OptionSet, Sendable {
  let rawValue: Int

  static let scopedInteractions = AXBridgeDisplayCapabilities(rawValue: 1 << 0)
  static let scopedTrees = AXBridgeDisplayCapabilities(rawValue: 1 << 1)
  static let scopedQuiescence = AXBridgeDisplayCapabilities(rawValue: 1 << 2)
}

enum AXBridgeDisplayInventory {
  static func decode(_ data: Data, requiring capabilities: AXBridgeDisplayCapabilities = []) throws -> [SimulatorAccessibilityDisplay] {
    if let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      response["ok"] as? Bool == false, response["error_kind"] as? String == "capability_unavailable"
    {
      throw SimulatorDisplayInteractionError.unsupportedCapability("accessibility display discovery")
    }
    let response = try AXBridgeResponse.validated(data, context: "display inventory")
    if capabilities.contains(.scopedInteractions), response["displayScopedInteractions"] as? Bool != true {
      throw SimulatorDisplayInteractionError.unsupportedCapability("display-scoped accessibility interactions in this guest")
    }
    if capabilities.contains(.scopedTrees), response["displayScopedTrees"] as? Bool != true {
      throw SimulatorDisplayInteractionError.unsupportedCapability("display-scoped accessibility trees in this guest")
    }
    if capabilities.contains(.scopedQuiescence), response["displayScopedQuiescence"] as? Bool != true {
      throw SimulatorDisplayInteractionError.unsupportedCapability("display-scoped quiescence in this guest")
    }
    struct Envelope: Decodable {
      let displays: [SimulatorAccessibilityDisplay]
    }
    guard let displays = try? JSONDecoder().decode(Envelope.self, from: data).displays,
      displays.count <= 32,
      displays.allSatisfy({ !$0.uniqueID.isEmpty && $0.uniqueID.count <= 1024 && $0.displayID > 0 }),
      Set(displays.map(\.uniqueID)).count == displays.count,
      Set(displays.map(\.displayID)).count == displays.count
    else { throw AXBridgeError.guestFailure("Invalid accessibility display inventory") }
    return displays
  }
}

extension SimulatorDisplayInteractionContext {
  static func join(
    display: SimulatorDisplay,
    touchscreens: [SimulatorTouchscreen],
    accessibility: [SimulatorAccessibilityDisplay],
    generation: UInt64
  ) throws -> SimulatorDisplayInteractionContext {
    let matchingTouchscreens = touchscreens.filter { $0.displayUniqueID == display.uniqueID }
    let matchingAccessibility = accessibility.filter { $0.uniqueID == display.uniqueID }
    guard matchingTouchscreens.count == 1, let touchscreen = matchingTouchscreens.first,
      matchingAccessibility.count == 1, let axDisplay = matchingAccessibility.first,
      touchscreen.digitizerTarget > 0, axDisplay.displayID > 0
    else { throw SimulatorDisplayInteractionError.missingMapping(display.uniqueID) }
    return SimulatorDisplayInteractionContext(
      display: display, accessibilityDisplayID: axDisplay.displayID, digitizerTarget: touchscreen.digitizerTarget, generation: generation)
  }
}

extension DisplayCommands {

  /// Resolves the active integrated display and both of its identities from fresh inventories, even for a sole
  /// display that routing reaches without naming it. An explicit UUID must identify the active display.
  func interactionContext(for displayUniqueID: String?, transport: any AXBridgeTransport) async throws -> SimulatorDisplayInteractionContext {
    let display: SimulatorDisplay
    switch try await resolveDisplay() {
    case .transitioning:
      throw SimulatorDisplayError.transitioning
    case .fallback, .target(.sole(.legacy)):
      throw SimulatorDisplayInteractionError.unsupportedCapability("display identities")
    case let .target(.sole(.identified(identified))), let .target(.selected(identified)):
      display = identified
    }
    if let displayUniqueID, displayUniqueID != display.uniqueID {
      throw SimulatorDisplayInteractionError.inactiveDisplay(displayUniqueID)
    }
    let touchscreens = try await touchscreens()
    let accessibility = try AXBridgeDisplayInventory.decode(await transport.send(.displays))
    try await validate(.identified(display))
    guard let configuration = configurationTracker.latest, configuration.active?.hasSameConfiguration(as: display) == true else {
      throw SimulatorDisplayError.changed
    }
    return try SimulatorDisplayInteractionContext.join(
      display: display, touchscreens: touchscreens, accessibility: accessibility, generation: configuration.generation)
  }

  /// Compares the observed identity, geometry and routing. No new display is substituted on mismatch.
  func validate(_ context: SimulatorDisplayInteractionContext, transport: any AXBridgeTransport) async throws {
    let current = try await interactionContext(for: nil, transport: transport)
    guard current.generation == context.generation else {
      throw SimulatorDisplayError.changed
    }
    guard current.display.hasSameConfiguration(as: context.display),
      current.accessibilityDisplayID == context.accessibilityDisplayID,
      current.digitizerTarget == context.digitizerTarget
    else { throw SimulatorDisplayError.changed }
  }
}
