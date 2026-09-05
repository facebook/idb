/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import Darwin
@preconcurrency import FBControlCore
import Foundation

/**
 The HID abstraction layer for a Simulator.

 Touch, button, and keyboard events are delivered through a pluggable `FBSimulatorHIDTransport`
 (the legacy Indigo `SimDeviceLegacyHIDClient` path by default). The remaining event families are
 not transport-switchable and are sent directly from here:

 1. PurpleWorkspacePort — for GSEvent-based events (e.g., device orientation changes).
    Payloads are constructed by `FBSimulatorPurpleHID` and sent via raw `mach_msg`.
    Guest-side: `GraphicsServices._PurpleEventCallback` → backboardd.

 2. Darwin notifications — e.g. shake, in-call status bar — posted via the SimDevice.

 See `Indigo.h` and `GSEvent.h` for wire format documentation.

 Indigo-family sends are serialized by the transport, so the type is `@unchecked Sendable`.
 */
public final class FBSimulatorHID: CustomStringConvertible, @unchecked Sendable {

  // MARK: Properties

  /// The transport for the touch / button / keyboard primitives.
  private let transport: FBSimulatorHIDTransport
  /// The transport for GSEvents (orientation, lock).
  private let purple: FBSimulatorPurpleHIDTransport
  /// The transport for the Darwin-notification inputs (shake, in-call status bar).
  private let notification: FBSimulatorDarwinNotificationTransport

  private weak var simulator: FBSimulator?

  /// Whether `send(event:logger:)` flushes the transport after every event (a fixed wait — see
  /// `FBSimulatorDTUHIDTransport.drainNanos`). A caller streaming many gestures over one open HID should
  /// set this to `false` and call `flush()` once before releasing the HID.
  public var flushesAfterEachEvent = true

  // MARK: Initializers

  /// `transport` forces a HID path; `nil` negotiates one (see `transport(for:requested:)`). Throws if the
  /// transport cannot be established (registration may need to occur prior to booting).
  public convenience init(
    for simulator: FBSimulator, transport transportType: FBSimulatorHIDTransportType? = nil
  ) throws {
    self.init(
      transport: try Self.transport(for: simulator, requested: transportType),
      purple: FBSimulatorPurpleHIDTransport(simulator: simulator),
      notification: FBSimulatorDarwinNotificationTransport(simulator: simulator),
      simulator: simulator)
  }

  /// A requested transport is never substituted — it is established or the error surfaces. With no request,
  /// `defaultHIDTransport` is tried and only an `isDTUHIDUnreachable` failure falls back to Indigo; a fault
  /// in an established transport is a real error. Reachability cannot be known up front: `dtuhidd` is
  /// demand-launched, so the service lookup that builds the transport is the only probe.
  private static func transport(
    for simulator: FBSimulator, requested: FBSimulatorHIDTransportType?
  ) throws -> FBSimulatorHIDTransport {
    if let requested {
      return try transport(requested, for: simulator)
    }
    let logger = FBControlCoreGlobalConfiguration.defaultLogger
    let preferred = simulator.defaultHIDTransport
    do {
      let transport = try transport(preferred, for: simulator)
      logger.log("Negotiated the \(preferred) HID transport")
      return transport
    } catch let error as FBSimulatorHIDError where error.isDTUHIDUnreachable {
      logger.log(
        "dtuhidd is unreachable (\(error.localizedDescription)), falling back to the legacy Indigo HID transport")
      return .indigo(try FBSimulatorIndigoHIDTransport.indigo(for: simulator))
    }
  }

  private static func transport(
    _ type: FBSimulatorHIDTransportType, for simulator: FBSimulator
  ) throws -> FBSimulatorHIDTransport {
    switch type {
    case .indigo:
      return .indigo(try FBSimulatorIndigoHIDTransport.indigo(for: simulator))
    case .dtuhid:
      return .dtuhid(try FBSimulatorDTUHIDTransport.dtuhid(for: simulator))
    }
  }

  /// `simulator` is weak and may be absent: the Purple and Darwin paths need it and throw
  /// `FBWeakTargetError.simulator` without one; the transport primitives never touch it.
  init(
    transport: FBSimulatorHIDTransport,
    purple: FBSimulatorPurpleHIDTransport,
    notification: FBSimulatorDarwinNotificationTransport,
    simulator: FBSimulator?
  ) {
    self.transport = transport
    self.purple = purple
    self.notification = notification
    self.simulator = simulator
  }

  // MARK: Lifecycle

  /**
   Disconnects from the remote HID.
   */
  public func disconnect() {
    transport.disconnect()
  }

  // MARK: Indigo Event Send Primitives

  /// Sends a single-finger touch at the given point (in points), optionally tagged as originating at
  /// a screen edge.
  func sendTouch(
    direction: FBSimulatorHIDDirection, x: Double, y: Double, edge: FBSimulatorHIDEdge
  ) async throws {
    try await transport.sendTouch(direction: direction, x: x, y: y, edge: edge)
  }

  /// Sends a two-finger touch (for multi-touch gestures) at the given points (in points).
  func sendTwoFingerTouch(direction: FBSimulatorHIDDirection, finger1: CGPoint, finger2: CGPoint) async throws {
    try await transport.sendTwoFingerTouch(direction: direction, finger1: finger1, finger2: finger2)
  }

  /// Sends a hardware button event.
  func sendButton(direction: FBSimulatorHIDDirection, button: FBSimulatorHIDButton) async throws {
    try await transport.sendButton(direction: direction, button: button)
  }

  /// Sends a keyboard key event.
  func sendKeyboard(direction: FBSimulatorHIDDirection, keyCode: UInt32) async throws {
    try await transport.sendKeyboard(direction: direction, keyCode: keyCode)
  }

  /// Drains the transport so `dtuhidd` consumes a gesture before the connection is torn down. Only DTUHID
  /// has anything to drain; Indigo's client is synchronous. `send(event:logger:)` calls this per event
  /// unless `flushesAfterEachEvent` is `false`.
  public func flush() async throws {
    guard case let .dtuhid(dtuhid) = transport else {
      return
    }
    try await dtuhid.flush()
  }

  /// Indigo only: the tvOS trackpad rides a dedicated Indigo service that `dtuhidd` does not expose (its
  /// digitizer targets are displays and its scroll targets rotary devices).
  func sendTrackpad(point: FBSimulatorTrackpadPoint, phase: FBSimulatorTrackpadPhase) async throws {
    guard case let .indigo(indigo) = transport else {
      throw FBSimulatorHIDError.notImplementedOnDTUHIDTransport(
        operation: "trackpad pan — the tvOS Siri Remote trackpad is not exposed by dtuhidd")
    }
    try await indigo.sendTrackpad(point: point, phase: phase)
  }

  // MARK: Purple / GSEvents

  /// Rotates the device. Delivered as a GSEvent over Purple, not through the HID transport.
  func sendOrientation(_ orientation: FBSimulatorHIDDeviceOrientation) async throws {
    try await purple.sendOrientation(orientation)
  }

  /// Locks the device. Delivered as a GSEvent over Purple, not through the HID transport.
  func sendLockDevice() async throws {
    try await purple.sendLockDevice()
  }

  // MARK: Darwin Notifications

  /// Shakes the device. Posted as a Darwin notification, not through the HID transport.
  func sendShake() async throws {
    try await notification.sendShake()
  }

  /// Toggles the in-call status bar. Posted as a Darwin notification, not through the HID transport.
  func sendToggleInCallStatusBar() async throws {
    try await notification.sendToggleInCallStatusBar()
  }

  // MARK: Dispatch

  /// Sends a (possibly composite) event, logging each sub-event, then drains once if any sub-event reached
  /// the HID transport — so a tap or typed string settles once, not per primitive.
  public func send(event: FBSimulatorHIDEvent, logger: FBControlCoreLogger) async throws {
    var wroteToTransport = false
    for subEvent in event.subEvents ?? [event] {
      switch subEvent {
      case let .delay(duration):
        logger.log("Delay \(duration)s")
      case .touch, .button, .keyboard, .twoFingerTouch, .trackpad,
        .deviceOrientation, .lockDevice, .shake, .toggleInCallStatusBar, .composite:
        logger.log("Sending \(subEvent)")
      }
      if try await deliver(subEvent) {
        wroteToTransport = true
      }
    }
    if wroteToTransport, flushesAfterEachEvent {
      try await flush()
    }
  }

  /// Routes one event to its transport; returns whether it went to the HID transport (which decides the drain).
  func deliver(_ event: FBSimulatorHIDEvent) async throws -> Bool {
    switch event {
    case let .touch(direction, x, y, edge):
      try await transport.sendTouch(direction: direction, x: x, y: y, edge: edge)
      return true
    case let .button(direction, button):
      try await transport.sendButton(direction: direction, button: button)
      return true
    case let .keyboard(direction, keyCode):
      try await transport.sendKeyboard(direction: direction, keyCode: keyCode)
      return true
    case let .twoFingerTouch(direction, finger1, finger2):
      try await transport.sendTwoFingerTouch(direction: direction, finger1: finger1, finger2: finger2)
      return true
    case let .trackpad(phase, point):
      try await sendTrackpad(point: point, phase: phase)
      return true
    case let .deviceOrientation(orientation):
      try await sendOrientation(orientation)
      return false
    case .lockDevice:
      try await sendLockDevice()
      return false
    case .shake:
      try await sendShake()
      return false
    case .toggleInCallStatusBar:
      try await sendToggleInCallStatusBar()
      return false
    case let .delay(duration):
      try await Task.sleep(nanoseconds: UInt64(max(0, duration) * 1_000_000_000))
      return false
    case let .composite(events):
      var wrote = false
      for event in events where try await deliver(event) {
        wrote = true
      }
      return wrote
    }
  }

  // MARK: CustomStringConvertible

  public var description: String {
    "SimulatorKit HID"
  }
}
