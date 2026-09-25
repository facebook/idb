/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import XPC

public enum SimulatorDisplayRotation: String, Sendable, Decodable {
  case upright = "rot0"
  case clockwise = "rot90"
  case upsideDown = "rot180"
  case counterclockwise = "rot270"
}

/// Interface geometry, independent of accessibility and touchscreen routing identities.
public struct SimulatorDisplayGeometry: Equatable, Sendable {
  public let bounds: CGRect
  public let scale: Double
  public let rotation: SimulatorDisplayRotation

  public var pointSize: CGSize {
    let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
    switch rotation {
    case .upright, .upsideDown: return size
    case .clockwise, .counterclockwise: return CGSize(width: size.height, height: size.width)
    }
  }

  /// Converts display-relative points to the unrotated point coordinates used by accessibility hit testing.
  public func unrotatedPoint(from point: CGPoint) throws -> CGPoint {
    let size = pointSize
    guard point.x.isFinite, point.y.isFinite,
      point.x >= 0, point.y >= 0, point.x <= size.width, point.y <= size.height
    else { throw SimulatorDisplayInteractionError.invalidPoint }
    let width = bounds.width / scale
    let height = bounds.height / scale
    switch rotation {
    case .upright: return point
    case .clockwise: return CGPoint(x: point.y, y: height - point.x)
    case .upsideDown: return CGPoint(x: width - point.x, y: height - point.y)
    case .counterclockwise: return CGPoint(x: width - point.y, y: point.x)
    }
  }
}

/// A legacy provider can describe its sole integrated display without identifying it.
public enum SimulatorInteractionDisplay: Equatable, Sendable {
  case identified(SimulatorDisplay)
  case legacy(SimulatorDisplayGeometry)

  func hasSameConfiguration(as other: Self) -> Bool {
    switch (self, other) {
    case let (.identified(first), .identified(second)): first.hasSameConfiguration(as: second)
    case let (.legacy(first), .legacy(second)): first == second
    case (.identified, .legacy), (.legacy, .identified): false
    }
  }

  public var geometry: SimulatorDisplayGeometry {
    switch self {
    case let .identified(display): display.geometry
    case let .legacy(geometry): geometry
    }
  }
}

public enum SimulatorDisplayActivitySource: Equatable, Sendable {
  case layout
  /// Identifies an actively illuminated display when layout activity is unavailable.
  case backlight
}

/// A current display snapshot. Activity evidence is independent of IO port power.
public struct SimulatorDisplay: Equatable, Sendable {
  public let uniqueID: String
  public let name: String
  public let isActive: Bool
  public let activitySource: SimulatorDisplayActivitySource

  /// The provider's explicit layout activity, absent when selection used backlight evidence.
  public var reportedActivity: Bool? { activitySource == .layout ? isActive : nil }
  public let isPrimary: Bool
  public let isIntegrated: Bool
  /// Bounds in the display's unrotated pixel coordinate space.
  public let bounds: CGRect
  public let scale: Double
  public let rotation: SimulatorDisplayRotation

  init(
    uniqueID: String, name: String, isActive: Bool, isPrimary: Bool, isIntegrated: Bool,
    bounds: CGRect, scale: Double, rotation: SimulatorDisplayRotation,
    activitySource: SimulatorDisplayActivitySource = .layout
  ) {
    self.uniqueID = uniqueID
    self.name = name
    self.isActive = isActive
    self.isPrimary = isPrimary
    self.isIntegrated = isIntegrated
    self.bounds = bounds
    self.scale = scale
    self.rotation = rotation
    self.activitySource = activitySource
  }

  public var geometry: SimulatorDisplayGeometry {
    SimulatorDisplayGeometry(bounds: bounds, scale: scale, rotation: rotation)
  }

  // Layout lookup may succeed on one snapshot and require backlight evidence on the next.
  func hasSameConfiguration(as other: Self) -> Bool {
    uniqueID == other.uniqueID && isActive == other.isActive && isIntegrated == other.isIntegrated && geometry == other.geometry
  }

  /// Pixel dimensions after applying the current interface rotation.
  public var size: CGSize {
    switch rotation {
    case .upright, .upsideDown: bounds.size
    case .clockwise, .counterclockwise: CGSize(width: bounds.height, height: bounds.width)
    }
  }
}

public enum SimulatorDisplayError: Error, LocalizedError {
  case noActiveIntegratedDisplay
  case ambiguousActiveDisplays([String])
  case changed
  case screensNotReported(within: TimeInterval)

  public var errorDescription: String? {
    switch self {
    case let .screensNotReported(seconds): "Simulator did not report its displays within \(seconds) seconds"
    case .noActiveIntegratedDisplay: "Simulator has no active integrated display"
    case let .ambiguousActiveDisplays(ids): "Simulator has multiple active integrated displays: \(ids.joined(separator: ", "))"
    case .changed: "Simulator display changed during the operation"
    }
  }
}

/// Memoized per `Simulator` through its command cache, so display identities learned by one
/// interaction route the next.
// SAFETY: `identities` is lock-guarded and the weak simulator reference is only ever read.
// patternlint-disable-next-line unchecked-sendable
public final class SimulatorDisplayCommands: DisplayCommands, @unchecked Sendable {
  private weak var simulator: Simulator?
  let identities = DisplayIdentityCache()

  public class func commands(with simulator: Simulator) -> SimulatorDisplayCommands {
    SimulatorDisplayCommands(simulator: simulator)
  }

  private init(simulator: Simulator) {
    self.simulator = simulator
  }

  /// Reads current displays with explicit layout activity or complete per-display backlight evidence.
  public func list() async throws -> [SimulatorDisplay] {
    try await read(decode: SimulatorDisplayProtocol.displays)
  }

  /// Resolves current interface geometry. Legacy selection requires exactly one integrated display.
  public func interactionDisplay() async throws -> SimulatorInteractionDisplay {
    try await read(decode: SimulatorDisplayProtocol.interactionDisplay)
  }

  /// Resolves the active integrated display and whether interactions have to name it.
  func interactionTarget() async throws -> SimulatorDisplayTarget {
    try await read(decode: SimulatorDisplayProtocol.interactionTarget)
  }

  /// Lists connected touchscreens. Match `displayUniqueID` to a display snapshot before routing input.
  public func touchscreens() async throws -> [SimulatorTouchscreen] {
    // Universal HID can advertise a virtual digitizer even when the target has no touch display.
    let simulator = try target()
    guard simulator.productFamily.hasTouchscreen else { return [] }
    return try await simulator.coreDevice.send(
      service: SimulatorTouchscreenProtocol.service, message: SimulatorTouchscreenProtocol.request(),
      decode: SimulatorTouchscreenProtocol.touchscreens)
  }

  /// Resolves one active integrated display and its independent accessibility and input identities.
  /// An explicit UUID must identify the active integrated display; inactive interaction is unsupported.
  public func interactionContext(for displayUniqueID: String? = nil) async throws -> SimulatorDisplayInteractionContext {
    try await interactionResolver(transport: AXBridgeOneshotTransport(simulator: target()))
      .resolve(displayUniqueID: displayUniqueID)
  }

  /// Fails if the observed active display, geometry or routing no longer matches the saved context.
  /// This is a fresh snapshot comparison, not a record of every intervening display transition.
  public func validate(_ context: SimulatorDisplayInteractionContext) async throws {
    try await interactionResolver(transport: AXBridgeOneshotTransport(simulator: target())).validate(context)
  }

  func interactionResolver(transport: any AXBridgeTransport) -> SimulatorDisplayInteractionResolver {
    SimulatorDisplayInteractionResolver(
      readDisplays: { try await self.list() },
      readTouchscreens: { try await self.touchscreens() },
      readAccessibility: { try AXBridgeDisplayInventory.decode(await transport.send(.displays)) })
  }

  /// Returns nil only when the runtime lacks the feature, or the provider the fields, needed to
  /// select a display.
  func activeIntegratedDisplayIfSupported() async throws -> SimulatorDisplay? {
    let snapshot = try await target().coreDevice.performIfSupported(
      action: SimulatorDisplayProtocol.action, service: SimulatorDisplayProtocol.service, input: CoreDeviceEmptyInput(),
      decode: SimulatorDisplayProtocol.snapshot)
    switch snapshot {
    case let .displays(displays): return try Self.activeIntegratedDisplay(in: displays)
    case .legacyProvider, nil: return nil
    }
  }

  private func target() throws -> Simulator {
    guard let simulator else { throw WeakTargetError.simulator }
    return simulator
  }

  private func read<Response: Sendable>(decode: @escaping @Sendable (xpc_object_t) throws -> Response) async throws -> Response {
    try await target().coreDevice.perform(
      action: SimulatorDisplayProtocol.action, service: SimulatorDisplayProtocol.service, input: CoreDeviceEmptyInput(), decode: decode)
  }

  public func activeIntegratedDisplay() async throws -> SimulatorDisplay {
    try Self.activeIntegratedDisplay(in: await list())
  }

  static func activeIntegratedDisplay(in displays: [SimulatorDisplay]) throws -> SimulatorDisplay {
    let active = displays.filter { $0.isActive && $0.isIntegrated }
    guard let display = active.first else { throw SimulatorDisplayError.noActiveIntegratedDisplay }
    guard active.count == 1 else { throw SimulatorDisplayError.ambiguousActiveDisplays(active.map(\.uniqueID)) }
    return display
  }
}
