/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

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
    else { throw SimulatorDisplayInteractionError.invalidPoint(point, bounds: size) }
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
enum SimulatorInteractionDisplay: Equatable, Sendable {
  case identified(SimulatorDisplay)
  case legacy(SimulatorDisplayGeometry)

  func hasSameConfiguration(as other: Self) -> Bool {
    switch (self, other) {
    case let (.identified(first), .identified(second)): first.hasSameConfiguration(as: second)
    case let (.legacy(first), .legacy(second)): first == second
    case (.identified, .legacy), (.legacy, .identified): false
    }
  }

  var geometry: SimulatorDisplayGeometry {
    switch self {
    case let .identified(display): display.geometry
    case let .legacy(geometry): geometry
    }
  }
}

public enum SimulatorDisplayActivity: Equatable, Sendable {
  case active
  case inactive
  /// The runtime reports a backlight state of `unknown`.
  case unknown
}

/// A current display snapshot. Activity evidence is independent of IO port power.
public struct SimulatorDisplay: Equatable, Sendable {
  public let uniqueID: String
  public let name: String
  public let activity: SimulatorDisplayActivity

  public var isActive: Bool { activity == .active }
  public let isPrimary: Bool
  public let isIntegrated: Bool
  /// Bounds in the display's unrotated pixel coordinate space.
  public let bounds: CGRect
  public let scale: Double
  public let rotation: SimulatorDisplayRotation

  init(
    uniqueID: String, name: String, activity: SimulatorDisplayActivity, isPrimary: Bool, isIntegrated: Bool,
    bounds: CGRect, scale: Double, rotation: SimulatorDisplayRotation
  ) {
    self.uniqueID = uniqueID
    self.name = name
    self.activity = activity
    self.isPrimary = isPrimary
    self.isIntegrated = isIntegrated
    self.bounds = bounds
    self.scale = scale
    self.rotation = rotation
  }

  public var geometry: SimulatorDisplayGeometry {
    SimulatorDisplayGeometry(bounds: bounds, scale: scale, rotation: rotation)
  }

  func hasSameConfiguration(as other: Self) -> Bool {
    uniqueID == other.uniqueID && activity == other.activity && isIntegrated == other.isIntegrated && geometry == other.geometry
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
  case changed
  /// Layout has moved to another display whose backlight has not caught up, as after a hinge change.
  case transitioning
  case screensNotReported(within: TimeInterval)

  public var errorDescription: String? {
    switch self {
    case let .screensNotReported(seconds): "Simulator did not report its displays within \(seconds) seconds"
    case .changed: "Simulator display changed during the operation"
    case .transitioning: "Simulator display is still changing: layout has moved to a display that is not lit yet"
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

  /// Only cancellation and a released simulator throw; every CoreDevice failure is reported.
  func report() async throws -> SimulatorDisplayReport {
    do {
      return try await target().coreDevice.perform(
        action: SimulatorDisplayProtocol.action, service: SimulatorDisplayProtocol.service, input: CoreDeviceEmptyInput(),
        decode: SimulatorDisplayProtocol.report)
    } catch let error as SimulatorCoreDeviceError {
      return .failed(error)
    }
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
    try await interactionContext(for: displayUniqueID, transport: AXBridgeOneshotTransport(simulator: target()))
  }

  /// Fails if the observed active display, geometry or routing no longer matches the saved context.
  /// This is a fresh snapshot comparison, not a record of every intervening display transition.
  public func validate(_ context: SimulatorDisplayInteractionContext) async throws {
    try await validate(context, transport: AXBridgeOneshotTransport(simulator: target()))
  }

  private func target() throws -> Simulator {
    guard let simulator else { throw WeakTargetError.simulator }
    return simulator
  }
}
