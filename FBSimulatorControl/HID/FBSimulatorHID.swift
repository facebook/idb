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

  /// Default Mach send timeout (in milliseconds) for the `sendPurpleEvent:` convenience wrapper.
  /// Healthy round-trips return in low single-digit milliseconds; 2000ms absorbs scheduler jitter
  /// while bounding the wedge condition where SpringBoard's PurpleWorkspacePort receive queue fills.
  private static let defaultPurpleSendTimeoutMs: mach_msg_timeout_t = 2000

  // MARK: Properties

  /// The transport for the touch / button / keyboard primitives.
  private let transport: FBSimulatorHIDTransport
  /// The Purple/GSEvent payload builder (orientation, lock).
  public let purple: FBSimulatorPurpleHID

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
      transport = try FBSimulatorIndigoHIDTransport.indigo(for: simulator)
    case .dtuhid:
      transport = try FBSimulatorDTUHIDTransport.dtuhid(for: simulator)
    }
    self.init(transport: transport, purple: FBSimulatorPurpleHID(), simulator: simulator)
  }

  private init(transport: FBSimulatorHIDTransport, purple: FBSimulatorPurpleHID, simulator: FBSimulator) {
    self.transport = transport
    self.purple = purple
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

  /// Drains the transport once a gesture's primitives have all been sent (see
  /// `FBSimulatorHIDTransport.flush`). `FBSimulatorHIDEvent.send(on:logger:)` calls this once per
  /// dispatched event; the individual `send*` primitives do not.
  func flush() async throws {
    try await transport.flush()
  }

  // MARK: Purple / GSEvents

  /**
   Sends a raw mach message to the simulator's PurpleWorkspacePort using a default 2000ms send timeout.
   */
  public func sendPurpleEvent(_ data: Data) throws {
    try sendPurpleEvent(data, timeoutMs: FBSimulatorHID.defaultPurpleSendTimeoutMs)
  }

  /**
   Sends a raw mach message to the simulator's PurpleWorkspacePort, bounded by an explicit send-side timeout.
   The `msgh_remote_port` field is patched with the PurpleWorkspacePort looked up from the simulator's
   bootstrap namespace. The send always uses `mach_msg(MACH_SEND_TIMEOUT)`; on `MACH_SEND_TIMED_OUT` the
   kernel guarantees the message is not enqueued.
   */
  public func sendPurpleEvent(_ data: Data, timeoutMs: mach_msg_timeout_t) throws {
    guard let simulator else {
      throw FBSimulatorHIDError.simulatorDeallocatedForPurpleEvent
    }

    var lookupError: NSError?
    let purplePort = simulator.device.lookup("PurpleWorkspacePort", error: &lookupError)
    if purplePort == 0 {
      throw FBSimulatorHIDError.purpleWorkspacePortUnavailable(underlying: lookupError)
    }

    // Copy the payload and patch msgh_remote_port with the looked-up port.
    var mutableData = data
    let kr: kern_return_t = mutableData.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> kern_return_t in
      guard let base = buffer.baseAddress else { return KERN_FAILURE }
      let header = base.assumingMemoryBound(to: mach_msg_header_t.self)
      header.pointee.msgh_remote_port = purplePort
      return mach_msg(
        header,
        MACH_SEND_MSG | MACH_SEND_TIMEOUT,
        header.pointee.msgh_size,
        0,
        mach_port_t(MACH_PORT_NULL),
        timeoutMs,
        mach_port_t(MACH_PORT_NULL))
    }

    if kr == KERN_SUCCESS {
      return
    }
    if kr == MACH_SEND_TIMED_OUT {
      throw FBSimulatorHIDError.machSendTimedOut(
        port: purplePort, timeoutMs: timeoutMs, detail: String(cString: mach_error_string(kr)))
    }
    throw FBSimulatorHIDError.machSendFailed(
      port: purplePort, detail: String(cString: mach_error_string(kr)), code: kr)
  }

  // MARK: Darwin Notifications

  /**
   Posts a Darwin notification to the simulator (e.g. shake, in-call status bar). Synchronous.
   */
  public func postDarwinNotification(_ notificationName: String) throws {
    guard let simulator else {
      throw FBSimulatorHIDError.simulatorDeallocatedForDarwinNotification
    }
    try simulator.device.postDarwinNotification(notificationName)
  }

  // MARK: CustomStringConvertible

  public var description: String {
    "SimulatorKit HID"
  }
}
