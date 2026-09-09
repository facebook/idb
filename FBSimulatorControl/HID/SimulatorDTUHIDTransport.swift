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

/// The waits `SimulatorDTUHIDTransport` performs around the events it sends.
enum DTUHIDTiming {

  /// Time to keep the connection alive after a gesture's events are sent, so `dtuhidd` consumes them
  /// before the connection is torn down. It resets its virtual services the instant the host peer
  /// disconnects, which for a one-shot gesture is the moment the host process exits.
  static let drainNanos: UInt64 = 80_000_000 // 80ms

  /// Time to wait for `dtuhidd` to activate the virtual services that carry events. It drops anything
  /// addressed to a service that is not yet active, logging `No active service, dropping event`.
  ///
  /// A fixed wait because no readiness signal has been found to wait on instead, not because none
  /// exists — what the daemon does with a message it cannot yet route has not been established. Sized
  /// above the observed activation gap.
  static let activationNanos: UInt64 = 500_000_000 // 500ms
}

/// Tracks the per-contact phase so that a stream of Indigo `.down`/`.up` events maps onto the
/// `dtuhidd` `start` / `position` / `end` model: the first `.down` is a `start`, subsequent `.down`s
/// (a drag/swipe) are `position`s, and `.up` is the `end`.
struct DigitizerContactTracker {
  private var active = false

  mutating func eventType(for direction: SimulatorHIDDirection) -> DigitizerEventType {
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

 An `actor`: the mutable contact state is actor-isolated, so the type needs no `@unchecked Sendable`.
 The XPC connection handle is thread-safe, so `disconnect()` cancels it from a `nonisolated` context.
 */
actor SimulatorDTUHIDTransport {

  static let digitizerServiceName = "com.apple.coredevice.feature.remote.hid.digitizer"

  // Private XPC endpoint functions, resolved at runtime (not in the XPC module headers).
  private typealias EndpointFromMachPortFn = @convention(c) (mach_port_t, UInt64, UInt64) -> xpc_object_t?
  private typealias ConnectionFromEndpointFn = @convention(c) (xpc_object_t) -> xpc_connection_t?
  private typealias EnableSim2HostFn = @convention(c) (xpc_connection_t) -> Void

  /// The host→guest XPC connection to `dtuhidd`. XPC connections are thread-safe, so it is marked
  /// `nonisolated(unsafe)` to be read from the `nonisolated` `disconnect()` as well as the
  /// actor-isolated send path.
  nonisolated(unsafe) private let connection: xpc_connection_t
  private let mainScreenSize: CGSize
  private let mainScreenScale: Float
  private let productFamily: FBControlCoreProductFamily
  private var contact = DigitizerContactTracker()
  private var twoFingerContact = DigitizerContactTracker()

  // MARK: - Initializers

  /// Builds a DTUHID transport for the provided Simulator and returns it ready to carry events.
  ///
  /// Async because readiness may need establishing before the transport can be handed out, and a
  /// caller should not have to remember to wait for it on every send.
  static func dtuhid(for simulator: FBSimulator) async throws -> SimulatorDTUHIDTransport {
    guard let handle = dlopen(nil, RTLD_NOW) else {
      throw SimulatorHIDError.dtuhidXPCSymbolsUnavailable
    }
    guard
      let endpointFromPort = symbol(handle, "xpc_endpoint_create_mach_port_4sim", as: EndpointFromMachPortFn.self),
      let connectionFromEndpoint = symbol(handle, "xpc_connection_create_from_endpoint", as: ConnectionFromEndpointFn.self),
      let enableSim2Host = symbol(handle, "xpc_connection_enable_sim2host_4sim", as: EnableSim2HostFn.self)
    else {
      throw SimulatorHIDError.dtuhidXPCSymbolsUnavailable
    }

    var lookupError: NSError?
    let servicePort = simulator.device.lookup(digitizerServiceName, error: &lookupError)
    if servicePort == 0 {
      throw SimulatorHIDError.dtuhidDigitizerServiceUnavailable(underlying: lookupError)
    }

    guard
      let endpoint = endpointFromPort(servicePort, 0, 0),
      let connection = connectionFromEndpoint(endpoint)
    else {
      throw SimulatorHIDError.dtuhidConnectionFailed
    }

    // The load-bearing step: without this the daemon observes the peer but never the payload.
    enableSim2Host(connection)
    xpc_connection_set_event_handler(connection) { _ in }
    xpc_connection_resume(connection)

    let transport = SimulatorDTUHIDTransport(
      connection: connection,
      mainScreenSize: simulator.device.deviceType.mainScreenSize,
      mainScreenScale: simulator.device.deviceType.mainScreenScale,
      productFamily: simulator.productFamily)
    do {
      try await transport.primeThenWait(nanoseconds: DTUHIDTiming.activationNanos)
    } catch {
      // The connection is live from `xpc_connection_resume` above, so an unreturned transport would
      // leave `dtuhidd` holding a peer nothing will ever send to.
      transport.disconnect()
      throw error
    }
    return transport
  }

  init(
    connection: xpc_connection_t,
    mainScreenSize: CGSize,
    mainScreenScale: Float,
    productFamily: FBControlCoreProductFamily
  ) {
    self.connection = connection
    self.mainScreenSize = mainScreenSize
    self.mainScreenScale = mainScreenScale
    self.productFamily = productFamily
  }

  private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as type: T.Type) -> T? {
    guard let sym = dlsym(handle, name) else {
      return nil
    }
    return unsafeBitCast(sym, to: type)
  }

  // MARK: - Sends

  nonisolated func disconnect() {
    xpc_connection_cancel(connection)
  }

  func sendTouch(
    direction: SimulatorHIDDirection, x: Double, y: Double, edge: FBSimulatorHIDEdge
  ) async throws {
    guard productFamily.hasTouchscreen else {
      throw SimulatorHIDError.touchUnsupportedOnAppleTV
    }
    let ratio = SimulatorIndigoHID.screenRatio(
      from: CGPoint(x: x, y: y), screenSize: mainScreenSize, screenScale: mainScreenScale)
    let event = IndigoDigitizerEvent(
      pointOne: DigitizerPoint(x: Double(ratio.x), y: Double(ratio.y)),
      eventType: contact.eventType(for: direction),
      edge: UInt64(edge.rawValue))
    try await send(messageType: "IndigoDigitizerEvent", payload: event)
  }

  func sendTwoFingerTouch(direction: SimulatorHIDDirection, finger1: CGPoint, finger2: CGPoint) async throws {
    guard productFamily.hasTouchscreen else {
      throw SimulatorHIDError.touchUnsupportedOnAppleTV
    }
    let r1 = SimulatorIndigoHID.screenRatio(from: finger1, screenSize: mainScreenSize, screenScale: mainScreenScale)
    let r2 = SimulatorIndigoHID.screenRatio(from: finger2, screenSize: mainScreenSize, screenScale: mainScreenScale)
    let event = IndigoDigitizerEvent(
      pointOne: DigitizerPoint(x: Double(r1.x), y: Double(r1.y)),
      pointTwo: DigitizerPoint(x: Double(r2.x), y: Double(r2.y)),
      eventType: twoFingerContact.eventType(for: direction))
    try await send(messageType: "IndigoDigitizerEvent", payload: event)
  }

  func sendButton(direction: SimulatorHIDDirection, button: FBSimulatorHIDButton) async throws {
    guard let usage = button.identity.consumerUsage else {
      throw SimulatorHIDError.notImplementedOnDTUHIDTransport(
        operation: "sendButton(.applePay) — Apple Pay is a double side-button press, not a single HID usage; send two .sideButton presses instead")
    }
    let state: HIDButtonState = direction == .down ? .down : .up
    try await send(
      messageType: "IndigoButtonEvent",
      payload: IndigoButtonEvent(usagePage: UInt64(usage.page), usageCode: UInt64(usage.code), state: state))
  }

  func sendKeyboard(direction: SimulatorHIDDirection, keyCode: UInt32) async throws {
    let state: HIDButtonState = direction == .down ? .down : .up
    try await send(
      messageType: "IndigoKeyboardButtonEvent",
      payload: IndigoKeyboardButtonEvent(usageCode: UInt64(keyCode), state: state))
  }

  /// Sends the keyboard usage the tvOS focus engine consumes. `dtuhidd` also advertises
  /// `com.apple.coredevice.feature.remote.hid.tvremote`, whose accepted usages are undocumented.
  func sendRemoteButton(direction: SimulatorHIDDirection, button: FBSimulatorHIDRemoteButton) async throws {
    try await sendKeyboard(direction: direction, keyCode: button.keyboardUsage)
  }

  // MARK: - Sending

  /// Wraps `payload` in a `DTUHIDMessage` and serializes it to the `xpc_object_t` `dtuhidd` decodes.
  nonisolated func encode(messageType: String, payload: some Encodable) throws -> xpc_object_t {
    let message = DTUHIDMessage(
      messageType: messageType, featureIdentifier: Self.digitizerServiceName, payload: payload)
    return try XPCEncoder().encode(message)
  }

  /// Encodes `payload` and writes it, resolving when the XPC send barrier fires. Does not wait for the
  /// daemon to consume the event — that is `flush()`'s job, run once per gesture rather than per
  /// primitive.
  ///
  /// Nothing suspends between a contact tracker assigning an event type and the write, so concurrent
  /// sends cannot deliver an `.end` ahead of the `.start` it followed.
  func send(messageType: String, payload: some Encodable) async throws {
    try await deliver(encode(messageType: messageType, payload: payload))
  }

  /// Opens the connection and waits for `dtuhidd` to activate the services that will carry events.
  ///
  /// An XPC connection is lazy: `xpc_connection_resume` does not create the peer, the first message
  /// does, and `dtuhidd` activates nothing until it has a peer. The first message therefore always
  /// predates any service that could receive it, so this spends one of its own rather than the
  /// caller's. Keyboard usage `0` is "no event indicated", inert even if it does outlive activation.
  func primeThenWait(nanoseconds: UInt64) async throws {
    try await deliver(
      encode(
        messageType: "IndigoKeyboardButtonEvent",
        payload: IndigoKeyboardButtonEvent(usageCode: 0, state: .up)))
    try await Task.sleep(nanoseconds: nanoseconds)
  }

  /// Writes an already-encoded message and resolves when the XPC send barrier fires.
  private func deliver(_ object: xpc_object_t) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      xpc_connection_send_message(connection, object)
      xpc_connection_send_barrier(connection) {
        continuation.resume()
      }
    }
  }

  /// Waits `DTUHIDTiming.drainNanos` so `dtuhidd` consumes a gesture before the connection is torn
  /// down. Once per gesture.
  func flush() async throws {
    try? await Task.sleep(nanoseconds: DTUHIDTiming.drainNanos)
  }

}
