/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XPC

public enum SimulatorDisplayRotation: String, Sendable {
  case upright = "rot0"
  case clockwise = "rot90"
  case upsideDown = "rot180"
  case counterclockwise = "rot270"
}

/// A current display snapshot. Activity is reported by CoreDevice independently of IO port power.
public struct SimulatorDisplay: Equatable, Sendable {
  public let uniqueID: String
  public let name: String
  public let isActive: Bool
  public let isPrimary: Bool
  public let isIntegrated: Bool
  /// Bounds in the display's unrotated pixel coordinate space.
  public let bounds: CGRect
  public let scale: Double
  public let rotation: SimulatorDisplayRotation

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
    case .changed: "Simulator display changed during capture"
    }
  }
}

public struct SimulatorDisplayCommands {
  private let simulator: Simulator

  public static func commands(with simulator: Simulator) -> SimulatorDisplayCommands {
    SimulatorDisplayCommands(simulator: simulator)
  }

  /// Reads configured displays. Requires a current report with explicit per-display activity.
  public func list() async throws -> [SimulatorDisplay] {
    try await read(decode: SimulatorDisplayProtocol.displays)
  }

  /// Lists connected touchscreens. Match `displayUniqueID` to a display snapshot before routing input.
  public func touchscreens() async throws -> [SimulatorTouchscreen] {
    // Universal HID can advertise a virtual digitizer even when the target has no touch display.
    guard simulator.productFamily.hasTouchscreen else { return [] }
    let queue = DispatchQueue(label: "com.facebook.FBSimulatorControl.touchscreen-info")
    let transport = try SimulatorCoreDeviceXPCTransport(
      simulator: simulator, service: SimulatorTouchscreenProtocol.service, queue: queue)
    return try await SimulatorCoreDeviceRequest<[SimulatorTouchscreen]>(transport: transport, queue: queue)
      .read(SimulatorTouchscreenProtocol.request(), decode: SimulatorTouchscreenProtocol.touchscreens)
  }

  /// Returns nil only when the provider lacks the capability needed to select a display.
  func activeIntegratedDisplayIfSupported() async throws -> SimulatorDisplay? {
    do {
      guard let displays = try await read(decode: SimulatorDisplayProtocol.captureDisplays) else { return nil }
      return try Self.activeIntegratedDisplay(in: displays)
    } catch SimulatorCoreDeviceError.unsupported(_) {
      return nil
    }
  }

  private func read<Response: Sendable>(decode: @escaping @Sendable (xpc_object_t) throws -> Response) async throws -> Response {
    let request = try SimulatorCoreDevice.request(
      action: "com.apple.coredevice.action.displayinfo", deviceID: simulator.udid,
      version: SimulatorCoreDevice.installedVersion(), input: SimulatorCoreDevice.dictionary([:]))
    let queue = DispatchQueue(label: "com.facebook.FBSimulatorControl.display-info")
    let transport = try SimulatorCoreDeviceXPCTransport(
      simulator: simulator, service: "com.apple.coredevice.feature.getdisplayinfo", queue: queue)
    return try await SimulatorCoreDeviceRequest<Response>(transport: transport, queue: queue)
      .read(request, decode: decode)
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
