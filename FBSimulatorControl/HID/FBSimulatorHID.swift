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

  // MARK: Initializers

  /**
   Creates a `FBSimulatorHID` for the provided Simulator.

   `transport` selects the HID path. When `nil` (the default) it is resolved with
   `FBSimulator.defaultHIDTransport` — the DTUHID transport when an active `dtuhidd` has suppressed
   the legacy HID, and the legacy Indigo path otherwise — so a caller that does not care gets a
   working transport without choosing one. Pass an explicit value to force a specific transport. Will
   fail if the chosen transport cannot be established for the provided Simulator (registration may
   need to occur prior to booting).
   */
  public convenience init(
    for simulator: FBSimulator, transport transportType: FBSimulatorHIDTransportType? = nil
  ) throws {
    let transport: FBSimulatorHIDTransport
    switch transportType ?? simulator.defaultHIDTransport {
    case .indigo:
      transport = .indigo(try FBSimulatorIndigoHIDTransport.indigo(for: simulator))
    case .dtuhid:
      transport = .dtuhid(try FBSimulatorDTUHIDTransport.dtuhid(for: simulator))
    }
    self.init(
      transport: transport,
      purple: FBSimulatorPurpleHIDTransport(simulator: simulator),
      notification: FBSimulatorDarwinNotificationTransport(simulator: simulator),
      simulator: simulator)
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

  /// Sends a single-finger touch at the given point (in points).
  func sendTouch(direction: FBSimulatorHIDDirection, x: Double, y: Double) async throws {
    try await transport.sendTouch(direction: direction, x: x, y: y)
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
  func flush() async throws {
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
  func sendOrientation(_ orientation: FBSimulatorHIDDeviceOrientation) throws {
    try purple.sendOrientation(orientation)
  }

  /// Locks the device. Delivered as a GSEvent over Purple, not through the HID transport.
  func sendLockDevice() throws {
    try purple.sendLockDevice()
  }

  // MARK: Darwin Notifications

  /// Shakes the device. Posted as a Darwin notification, not through the HID transport.
  func sendShake() throws {
    try notification.sendShake()
  }

  /// Toggles the in-call status bar. Posted as a Darwin notification, not through the HID transport.
  func sendToggleInCallStatusBar() throws {
    try notification.sendToggleInCallStatusBar()
  }

  // MARK: CustomStringConvertible

  public var description: String {
    "SimulatorKit HID"
  }
}
