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

 Touch, button, and keyboard events are delivered through a pluggable `SimulatorHIDTransport`
 (the legacy Indigo `SimDeviceLegacyHIDClient` path by default). The remaining event families are
 not transport-switchable and each has a transport of its own here:

 1. PurpleWorkspacePort — for GSEvent-based events: device lock, and device orientation on a
    runtime that does not report device motion. Payloads are constructed by `SimulatorPurpleHID`
    and sent via raw `mach_msg`. Guest-side: `GraphicsServices._PurpleEventCallback` → backboardd.

 2. Darwin notifications — e.g. shake, in-call status bar — posted via the SimDevice.

 3. Vendor-defined DTUHID reports — the hinge, and device orientation on a runtime that reports
    device motion. The `vendorDefined` connection owned by `simulator.hid`.

 Which of 1 and 3 carries a rotation is decided by the simulator's `MotionCapabilities`.

 See `Indigo.h` and `GSEvent.h` for wire format documentation.

 Indigo-family sends are serialized by the transport, so the type is `@unchecked Sendable`.
 */
public final class SimulatorHID: CustomStringConvertible, @unchecked Sendable {

  // MARK: - Properties

  /// The transport for the touch / button / keyboard primitives.
  private let transport: SimulatorHIDTransport

  private weak var simulator: Simulator?

  /// Whether `send(event:logger:)` flushes after every event. Streaming callers can disable this
  /// and call `flush()` before releasing the HID.
  public var flushesAfterEachEvent = true

  // MARK: - Initializers

  /// `transport` forces a HID path; `nil` negotiates one (see `transport(for:requested:)`). Throws if the
  /// transport cannot be established (registration may need to occur prior to booting).
  public convenience init(
    for simulator: Simulator, transport transportType: SimulatorHIDTransportType? = nil
  ) async throws {
    self.init(
      transport: try await Self.transport(for: simulator, requested: transportType),
      simulator: simulator)
  }

  /// A requested transport is never substituted — it is established or the error surfaces. With no request,
  /// `defaultHIDTransport` is tried and only an `isDTUHIDUnreachable` failure falls back to Indigo; a fault
  /// in an established transport is a real error. Reachability is settled where it is observable, by
  /// `SimulatorDTUHIDTransport.dtuhid(for:)` round-tripping a barrier past its retries: `dtuhidd` is
  /// demand-launched, so neither the toolchain version nor the service lookup can tell whether one is
  /// there. Falling back costs the keyboard, which the guest has already handed to `dtuhidd`, so it is
  /// reached only after that probe has given the daemon every chance to come up.
  private static func transport(
    for simulator: Simulator, requested: SimulatorHIDTransportType?
  ) async throws -> SimulatorHIDTransport {
    if let requested {
      return try await transport(requested, for: simulator)
    }
    let logger = ControlCoreGlobalConfiguration.defaultLogger
    let preferred = simulator.defaultHIDTransport
    do {
      let transport = try await transport(preferred, for: simulator)
      logger.log("Negotiated the \(preferred) HID transport")
      return transport
    } catch let error as SimulatorHIDError where error.isDTUHIDUnreachable {
      logger.log(
        "dtuhidd is unreachable (\(error.localizedDescription)), falling back to the legacy Indigo HID transport")
      return .indigo(try SimulatorIndigoHIDTransport.indigo(for: simulator))
    }
  }

  private static func transport(
    _ type: SimulatorHIDTransportType, for simulator: Simulator
  ) async throws -> SimulatorHIDTransport {
    switch type {
    case .indigo:
      return .indigo(try SimulatorIndigoHIDTransport.indigo(for: simulator))
    case .dtuhid:
      let dtuhid = try await SimulatorDTUHIDTransport.dtuhid(for: simulator)
      guard let indigo = indigoAlongsideDTUHID(for: simulator) else {
        return .dtuhid(dtuhid)
      }
      return .mixed(dtuhid: dtuhid, indigo: indigo)
    }
  }

  /// The Indigo transport to run alongside DTUHID, for a target that needs both.
  ///
  /// Only Apple TV does. It is the only family with a trackpad, which `dtuhidd` does not expose, and the
  /// only one where a second client is safe: Indigo and DTUHID both claim `mainTouchscreen` and
  /// whichever sends first on a boot keeps it, and tvOS has none for them to contend over.
  ///
  /// Absent rather than fatal when it cannot be registered, since it carries the trackpad alone — a
  /// failure should cost a pan, not every other input on the target.
  private static func indigoAlongsideDTUHID(for simulator: Simulator) -> SimulatorIndigoHIDTransport? {
    guard simulator.productFamily == .appleTV else {
      return nil
    }
    return try? SimulatorIndigoHIDTransport.indigo(for: simulator)
  }

  /// `simulator` is weak and may be absent: device actions need it and throw
  /// `WeakTargetError.simulator` without one; the transport primitives never touch it.
  init(transport: SimulatorHIDTransport, simulator: Simulator?) {
    self.transport = transport
    self.simulator = simulator
  }

  /// Drains pending events before disconnecting, even when the caller is cancelled.
  /// Drain errors do not prevent disconnection.
  public func close() async {
    let drain = Task { try await flush() }
    try? await drain.value
    transport.disconnect()
  }

  // MARK: - Input transport

  /// Drains the transport so `dtuhidd` consumes a gesture before the connection is torn down. Only DTUHID
  /// has anything to drain; Indigo's client is synchronous. `send(event:logger:)` calls this per event
  /// unless `flushesAfterEachEvent` is `false`.
  public func flush() async throws {
    try await transport.dtuhid?.flush()
  }

  /// Indigo only: the tvOS trackpad rides a dedicated Indigo service that `dtuhidd` does not expose (its
  /// digitizer targets are displays and its scroll targets rotary devices).
  func sendTrackpad(point: SimulatorTrackpadPoint, phase: SimulatorTrackpadPhase) async throws {
    guard let indigo = transport.indigo else {
      throw SimulatorHIDError.notImplementedOnDTUHIDTransport(
        operation: "trackpad pan — the tvOS Siri Remote trackpad is not exposed by dtuhidd")
    }
    try await indigo.sendTrackpad(point: point, phase: phase)
  }

  // MARK: - Purple / GSEvents and vendor reports

  func sendOrientation(_ orientation: SimulatorHIDDeviceOrientation) async throws {
    guard let simulator else { throw WeakTargetError.simulator }
    try await simulator.orientation.set(orientation, convention: .interface)
  }

  // MARK: - Dispatch

  /// Sends a (possibly composite) event, logging each sub-event, then drains once if any sub-event reached
  /// the HID transport — so a tap or typed string settles once, not per primitive.
  public func send(event: SimulatorHIDEvent, logger: ControlCoreLogger) async throws {
    var wroteToTransport = false
    for subEvent in event.subEvents ?? [event] {
      switch subEvent {
      case let .delay(duration):
        logger.log("Delay \(duration)s")
      case .touch, .button, .remoteButton, .keyboard, .twoFingerTouch, .trackpad,
        .deviceOrientation, .hinge, .lockDevice, .shake, .toggleInCallStatusBar, .composite:
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
  func deliver(_ event: SimulatorHIDEvent) async throws -> Bool {
    switch event {
    case let .touch(direction, x, y, edge):
      try await transport.sendTouch(direction: direction, x: x, y: y, edge: edge)
      return true
    case let .button(direction, button):
      try await transport.sendButton(direction: direction, button: button)
      return true
    case let .remoteButton(direction, button):
      try await transport.sendRemoteButton(direction: direction, button: button)
      return true
    case let .keyboard(direction, keyCode):
      try await transport.sendKeyboard(direction: direction, keyCode: keyCode)
      return true
    case let .twoFingerTouch(direction, finger1, finger2):
      try await transport.sendTwoFingerTouch(direction: direction, finger1: finger1, finger2: finger2)
      return true
    case let .trackpad(phase, point):
      try await sendTrackpad(point: point, phase: phase)
      // The trackpad rides Indigo, and only DTUHID has a drain, so this wrote to the drained transport
      // only on a target that has no DTUHID transport at all.
      return transport.dtuhid == nil
    case let .deviceOrientation(orientation):
      try await sendOrientation(orientation)
      return false
    case .lockDevice:
      guard let simulator else { throw WeakTargetError.simulator }
      try await simulator.hardware.lock()
      return false
    case let .hinge(angle):
      guard let simulator else { throw WeakTargetError.simulator }
      try await simulator.hinge.setAngle(angle)
      return false
    case .shake:
      guard let simulator else { throw WeakTargetError.simulator }
      try await simulator.hardware.shake()
      return false
    case .toggleInCallStatusBar:
      guard let simulator else { throw WeakTargetError.simulator }
      try await simulator.statusBar.toggleInCall()
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

  public var description: String {
    "SimulatorKit HID"
  }
}
