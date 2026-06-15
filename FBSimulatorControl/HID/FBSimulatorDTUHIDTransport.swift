/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
@preconcurrency import CoreSimulator
import Darwin
@preconcurrency import FBControlCore
import Foundation
import XPC

/// Tracks the per-contact phase so that a stream of Indigo `.down`/`.up` events maps onto the
/// `dtuhidd` `start` / `position` / `end` model: the first `.down` is a `start`, subsequent `.down`s
/// (a drag/swipe) are `position`s, and `.up` is the `end`.
struct DigitizerContactTracker {
  private var active = false

  mutating func eventType(for direction: FBSimulatorHIDDirection) -> DigitizerEventType {
    switch direction {
    case .down:
      if active {
        return .position
      }
      active = true
      return .start
    case .up:
      active = false
      return .end
    }
  }
}

/**
 The DTUHID transport (Xcode 27 / macOS 26 / iOS 26+).

 Drives the modern `dtuhidd` daemon: events cross the host→guest boundary as plain-XPC dictionaries
 delivered to the `com.apple.coredevice.feature.remote.hid.digitizer` service. Each message is built
 as an `Encodable` model (e.g. `IndigoDigitizerEvent`) wrapped in a `DTUHIDMessage` envelope and
 serialized with `XPCEncoder`, rather than hand-rolled `xpc_dictionary_set_*` calls. The host XPC
 connection is built from the simulator's Mach port via the private `_4sim` endpoint symbols
 (resolved with `dlsym`) and must be marked simulator-to-host with `xpc_connection_enable_sim2host_4sim`
 before messages reach the service handler.

 Capabilities are added one per commit; not-yet-implemented primitives throw
 `notImplementedOnDTUHIDTransport` rather than silently falling back to Indigo.

 An `actor`: the mutable contact state is actor-isolated, so the type needs no `@unchecked Sendable`.
 The XPC connection handle is thread-safe, so `disconnect()` cancels it from a `nonisolated` context.
 */
actor FBSimulatorDTUHIDTransport: FBSimulatorHIDTransport {

  static let digitizerServiceName = "com.apple.coredevice.feature.remote.hid.digitizer"

  // Private XPC endpoint functions, resolved at runtime (not in the XPC module headers).
  private typealias EndpointFromMachPortFn = @convention(c) (mach_port_t, UInt64, UInt64) -> xpc_object_t?
  private typealias ConnectionFromEndpointFn = @convention(c) (xpc_object_t) -> xpc_connection_t?
  private typealias EnableSim2HostFn = @convention(c) (xpc_connection_t) -> Void

  /// Time to keep the connection alive after a send so `dtuhidd` consumes the event before the
  /// connection can be torn down. `dtuhidd` resets its virtual services (dropping any in-flight
  /// gesture) the instant the host peer disconnects — which, for a one-shot gesture from a
  /// short-lived host process, is the moment that process exits right after the send. The XPC send
  /// barrier only confirms the message was flushed to the connection, not that the daemon consumed
  /// it, so we settle here. It also spaces a gesture's down/up so the guest registers a real
  /// gesture rather than a zero-duration blip.
  private static let settleNanos: UInt64 = 80_000_000 // 80ms

  /// The host→guest XPC connection to `dtuhidd`. XPC connections are thread-safe, so it is marked
  /// `nonisolated(unsafe)` to be read from the `nonisolated` `disconnect()` as well as the
  /// actor-isolated send path.
  nonisolated(unsafe) private let connection: xpc_connection_t
  private let mainScreenSize: CGSize
  private let mainScreenScale: Float
  private var contact = DigitizerContactTracker()

  // MARK: Initializers

  /// Builds a DTUHID transport for the provided Simulator, establishing the host XPC connection to
  /// `dtuhidd`. All setup is synchronous, so the returned transport is ready to send.
  static func dtuhid(for simulator: FBSimulator) throws -> FBSimulatorDTUHIDTransport {
    guard let handle = dlopen(nil, RTLD_NOW) else {
      throw FBSimulatorHIDError.dtuhidXPCSymbolsUnavailable
    }
    guard
      let endpointFromPort = symbol(handle, "xpc_endpoint_create_mach_port_4sim", as: EndpointFromMachPortFn.self),
      let connectionFromEndpoint = symbol(handle, "xpc_connection_create_from_endpoint", as: ConnectionFromEndpointFn.self),
      let enableSim2Host = symbol(handle, "xpc_connection_enable_sim2host_4sim", as: EnableSim2HostFn.self)
    else {
      throw FBSimulatorHIDError.dtuhidXPCSymbolsUnavailable
    }

    var lookupError: NSError?
    let servicePort = simulator.device.lookup(digitizerServiceName, error: &lookupError)
    if servicePort == 0 {
      throw FBSimulatorHIDError.dtuhidDigitizerServiceUnavailable(underlying: lookupError)
    }

    guard
      let endpoint = endpointFromPort(servicePort, 0, 0),
      let connection = connectionFromEndpoint(endpoint)
    else {
      throw FBSimulatorHIDError.dtuhidConnectionFailed
    }

    // The load-bearing step: without this the daemon observes the peer but never the payload.
    enableSim2Host(connection)
    xpc_connection_set_event_handler(connection) { _ in }
    xpc_connection_resume(connection)

    return FBSimulatorDTUHIDTransport(
      connection: connection,
      mainScreenSize: simulator.device.deviceType.mainScreenSize,
      mainScreenScale: simulator.device.deviceType.mainScreenScale)
  }

  init(connection: xpc_connection_t, mainScreenSize: CGSize, mainScreenScale: Float) {
    self.connection = connection
    self.mainScreenSize = mainScreenSize
    self.mainScreenScale = mainScreenScale
  }

  private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as type: T.Type) -> T? {
    guard let sym = dlsym(handle, name) else {
      return nil
    }
    return unsafeBitCast(sym, to: type)
  }

  // MARK: FBSimulatorHIDTransport

  nonisolated func disconnect() {
    xpc_connection_cancel(connection)
  }

  func sendTouch(direction: FBSimulatorHIDDirection, x: Double, y: Double) async throws {
    let ratio = FBSimulatorIndigoHID.screenRatio(
      from: CGPoint(x: x, y: y), screenSize: mainScreenSize, screenScale: mainScreenScale)
    let event = IndigoDigitizerEvent(
      pointOne: DigitizerPoint(x: Double(ratio.x), y: Double(ratio.y)),
      eventType: contact.eventType(for: direction))
    try await send(messageType: "IndigoDigitizerEvent", payload: event)
  }

  func sendTwoFingerTouch(direction: FBSimulatorHIDDirection, finger1: CGPoint, finger2: CGPoint) async throws {
    throw FBSimulatorHIDError.notImplementedOnDTUHIDTransport(operation: "sendTwoFingerTouch")
  }

  func sendButton(direction: FBSimulatorHIDDirection, button: FBSimulatorHIDButton) async throws {
    throw FBSimulatorHIDError.notImplementedOnDTUHIDTransport(operation: "sendButton")
  }

  func sendKeyboard(direction: FBSimulatorHIDDirection, keyCode: UInt32) async throws {
    let state: HIDButtonState = direction == .down ? .down : .up
    try await send(
      messageType: "IndigoKeyboardButtonEvent",
      payload: IndigoKeyboardButtonEvent(usageCode: UInt64(keyCode), state: state))
  }

  // MARK: Sending

  /// Wraps `payload` in a `DTUHIDMessage` and serializes it to the `xpc_object_t` `dtuhidd` decodes.
  /// Pure and stateless, so the envelope shape is unit-testable without a live daemon connection.
  nonisolated func encode(messageType: String, payload: some Encodable) throws -> xpc_object_t {
    let message = DTUHIDMessage(
      messageType: messageType, featureIdentifier: Self.digitizerServiceName, payload: payload)
    return try XPCEncoder().encode(message)
  }

  /// Encodes `payload`, sends it over the connection, and resolves when the XPC send barrier fires.
  /// The actor serializes calls, so per-gesture state stays consistent.
  func send(messageType: String, payload: some Encodable) async throws {
    let object = try encode(messageType: messageType, payload: payload)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      xpc_connection_send_message(connection, object)
      xpc_connection_send_barrier(connection) {
        continuation.resume()
      }
    }
    // Keep the connection alive long enough for dtuhidd to consume the event (see settleNanos).
    try? await Task.sleep(nanoseconds: Self.settleNanos)
  }
}
