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

  /// Whether `send(event:logger:)` flushes the transport after every event.
  ///
  /// The flush exists so a short-lived host process does not tear the connection down before the
  /// guest has consumed the gesture (see `FBSimulatorDTUHIDTransport.drainNanos`). It is a fixed
  /// wait, so it costs the same whether or not a teardown is coming.
  ///
  /// A caller that holds one `FBSimulatorHID` open across many gestures — a persistent session
  /// streaming a continuous gesture — has no teardown between events, so that wait is pure
  /// per-event latency, and at one flush per event it caps throughput well below the rate such a
  /// gesture produces. Those callers set this to `false` and call `flush()` once before releasing
  /// the HID. Defaults to `true`, so one-shot callers keep the safe behaviour without opting in.
  public var flushesAfterEachEvent = true

  // MARK: Initializers

  /**
   Creates a `FBSimulatorHID` for the provided Simulator.

   `transport` selects the HID path. Pass an explicit value to force one; pass `nil` (the default) to
   have one negotiated, so a caller that does not care gets a working transport without choosing one.
   Will fail if the chosen transport cannot be established for the provided Simulator (registration
   may need to occur prior to booting).
   */
  public convenience init(
    for simulator: FBSimulator, transport transportType: FBSimulatorHIDTransportType? = nil
  ) throws {
    self.init(
      transport: try Self.transport(for: simulator, requested: transportType),
      purple: FBSimulatorPurpleHIDTransport(simulator: simulator),
      notification: FBSimulatorDarwinNotificationTransport(simulator: simulator),
      simulator: simulator)
  }

  /// Establishes the transport the caller asked for, or negotiates one if they asked for nothing.
  ///
  /// A caller that named a transport gets that transport or an error — forcing `.dtuhid` to debug a
  /// DTUHID problem must not quietly hand back Indigo. A caller that named none gets
  /// `FBSimulator.defaultHIDTransport`, and if that turns out to be unreachable on this host, the
  /// other one. Only `isDTUHIDUnreachable` failures are negotiated around; a fault in a transport
  /// that was successfully established is a real error and surfaces.
  ///
  /// The preference cannot be resolved to a certainty up front: `dtuhidd` is demand-launched, so the
  /// only way to know whether it can be reached is to look its service up, which is what building the
  /// transport does.
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

  /// The designated initializer.
  ///
  /// `simulator` is held weakly and may be absent. The Purple and Darwin paths need it and throw
  /// `FBWeakTargetError.simulator` without one; the transport primitives never touch it. That
  /// asymmetry is what lets a test drive the transport with no simulator attached.
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

  /// Drains the transport once a gesture's primitives have all been sent, so `dtuhidd` consumes them
  /// before the connection is torn down. `FBSimulatorHIDEvent.send(on:logger:)` calls this once per
  /// dispatched event; the individual `send*` primitives do not.
  ///
  /// Only DTUHID has anything to drain. Indigo's client is synchronous, so there is nothing waiting on
  /// the far side and no drain to perform — which is why `flush` is not on the transport at all.
  ///
  /// `send(event:logger:)` calls this for you unless `flushesAfterEachEvent` is `false`, in which case
  /// a caller streaming a continuous gesture calls it once at the end rather than paying it per event.
  public func flush() async throws {
    guard case let .dtuhid(dtuhid) = transport else {
      return
    }
    try await dtuhid.flush()
  }

  /// Sends one phase of a tvOS Siri Remote trackpad gesture.
  ///
  /// The trackpad rides the dedicated Indigo trackpad service, which `dtuhidd` does not expose: its
  /// digitizer targets are displays (`DigitizerTarget` = mainScreen/display1..10) and its scroll targets
  /// are rotary devices (`ScrollTarget` = digitalCrown/dial) — none is the trackpad, and the tvOS guest
  /// registers no trackpad/pointer service. Asked here rather than on the transport, so DTUHID never
  /// declares a method it could only throw from.
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

  /// Sends a (possibly composite) HID event, then drains the transport if anything reached it.
  ///
  /// A `.composite` is flattened to its ordered sub-events so each is logged individually, and a
  /// `.delay` suspends the task; the single drain then runs after the whole event. So a tap (down + up)
  /// or a typed string settles once, not after every primitive — which keeps the gesture intact before
  /// the connection is torn down while avoiding a per-primitive stall on the DTUHID transport.
  ///
  /// The drain follows what was *written*, not what the event said it would write. Only DTUHID has
  /// anything to drain; Indigo's client is synchronous and has no `flush` to call.
  public func send(event: FBSimulatorHIDEvent, logger: FBControlCoreLogger) async throws {
    var wroteToTransport = false
    for subEvent in event.subEvents ?? [event] {
      // Listed rather than defaulted so a new case has to decide how it reads in the log, the same
      // way `deliver` makes it decide which transport carries it.
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

  /// Routes one event to the transport that carries it, reporting whether that transport was the HID
  /// one — which is what decides the drain.
  ///
  /// Exhaustive, so a new case cannot be added without deciding which transport delivers it. That is
  /// the whole reason the routing lives here rather than being predicted by a property on the event:
  /// a prediction can disagree with the dispatch, an observation cannot.
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
