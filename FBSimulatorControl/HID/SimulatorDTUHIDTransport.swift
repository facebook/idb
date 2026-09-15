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

  /// Time allowed for a warm connection to dispatch events before disconnecting.
  static let drain = Duration.milliseconds(80)

  /// Time allowed for device-open and dispatch after the barrier reply signals peer activation.
  static let replyTail = Duration.milliseconds(200)

  /// Deadline for a barrier reply before taking the fallback drain.
  static let replyTimeout = DispatchTimeInterval.seconds(2)

  /// Additional wait after the barrier deadline expires.
  static let fallbackDrain = Duration.seconds(1)
}

/// Injectable waits for the DTUHID transport.
struct DTUHIDDrainClock: Sendable {
  let sleep: @Sendable (Duration) async throws -> Void
  let awaitBarrierReply: @Sendable (xpc_connection_t, xpc_object_t) async throws -> Void

  static let live = DTUHIDDrainClock(
    sleep: { try await Task.sleep(for: $0) },
    awaitBarrierReply: { connection, message in
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        // SAFETY: The lock serializes the reply and timeout callbacks.
        // patternlint-disable-next-line unchecked-sendable
        final class BarrierReply: @unchecked Sendable {
          private let lock = NSLock()
          private var pending = true

          func finish(_ resume: () -> Void) {
            let shouldResume = lock.withLock {
              defer { pending = false }
              return pending
            }
            if shouldResume {
              resume()
            }
          }
        }
        let reply = BarrierReply()
        xpc_connection_send_message_with_reply(
          connection, message, DispatchQueue.global(qos: .userInitiated)
        ) { _ in
          // Any reply object ends the await, including an XPC error: a dead connection is past
          // protecting, and the tail that follows is harmless.
          reply.finish { continuation.resume() }
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
          deadline: .now() + DTUHIDTiming.replyTimeout
        ) {
          reply.finish { continuation.resume(throwing: DTUHIDDrainTimeout.expired) }
        }
      }
    })
}

/// A barrier deadline expired; `flush()` takes the fallback drain.
enum DTUHIDDrainTimeout: Error {
  case expired
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

  // SAFETY: XPC connections support concurrent sending and cancellation.
  // patternlint-disable-next-line swift-nonisolated-unsafe
  nonisolated(unsafe) private let connection: xpc_connection_t
  private let mainScreenSize: CGSize
  private let mainScreenScale: Float
  private let productFamily: FBControlCoreProductFamily
  private let clock: DTUHIDDrainClock
  private var contact = DigitizerContactTracker()
  private var twoFingerContact = DigitizerContactTracker()
  private var coldDrainState = ColdDrainState.pending
  // A drain claims a snapshot of the send count; later sends remain outstanding.
  private var sendGeneration = 0
  private var drainedGeneration = 0

  // MARK: - Initializers

  /// Connects to the simulator's DTUHID service. Events can be sent immediately.
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

    return SimulatorDTUHIDTransport(
      connection: connection,
      mainScreenSize: simulator.device.deviceType.mainScreenSize,
      mainScreenScale: simulator.device.deviceType.mainScreenScale,
      productFamily: simulator.productFamily)
  }

  init(
    connection: xpc_connection_t,
    mainScreenSize: CGSize,
    mainScreenScale: Float,
    productFamily: FBControlCoreProductFamily,
    clock: DTUHIDDrainClock = .live
  ) {
    self.connection = connection
    self.mainScreenSize = mainScreenSize
    self.mainScreenScale = mainScreenScale
    self.productFamily = productFamily
    self.clock = clock
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
    direction: SimulatorHIDDirection, x: Double, y: Double, edge: SimulatorHIDEdge
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

  func sendButton(direction: SimulatorHIDDirection, button: SimulatorHIDButton) async throws {
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
  func sendRemoteButton(direction: SimulatorHIDDirection, button: SimulatorHIDRemoteButton) async throws {
    try await sendKeyboard(direction: direction, keyCode: button.keyboardUsage)
  }

  // MARK: - Sending

  /// Wraps `payload` in a `DTUHIDMessage` and serializes it to the `xpc_object_t` `dtuhidd` decodes.
  nonisolated func encode(messageType: String, payload: some Encodable, isBarrier: Bool = false) throws -> xpc_object_t {
    let message = DTUHIDMessage(
      messageType: messageType,
      featureIdentifier: Self.digitizerServiceName,
      isBarrier: isBarrier,
      payload: payload)
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

  /// Writes an already-encoded message and resolves when the XPC send barrier fires.
  private func deliver(_ object: xpc_object_t) async throws {
    // Make the send visible to flush before the first suspension.
    sendGeneration += 1
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      xpc_connection_send_message(connection, object)
      xpc_connection_send_barrier(connection) {
        continuation.resume()
      }
    }
  }

  /// Allows time for events sent before this call to reach the guest before disconnecting.
  /// The first drain waits for a barrier reply plus `replyTail`; later drains wait `drain`.
  /// Returns immediately when no sends are outstanding.
  func flush() async throws {
    let generation = sendGeneration
    guard generation > drainedGeneration else {
      return
    }
    if case .done = coldDrainState {
      try await clock.sleep(DTUHIDTiming.drain)
    } else {
      let coldGeneration = try await coldDrain()
      if generation > coldGeneration {
        try await clock.sleep(DTUHIDTiming.drain)
      }
    }
    drainedGeneration = max(drainedGeneration, generation)
  }

  private enum ColdDrainState {
    case pending
    case running(Task<Int, Error>)
    case done
  }

  /// Returns the last send covered by the shared drain. Waiter cancellation leaves it running.
  private func coldDrain() async throws -> Int {
    if case let .running(task) = coldDrainState {
      return try await task.value
    }
    let generation = sendGeneration
    let task = Task<Int, Error> {
      do {
        try await self.performColdDrain()
      } catch {
        self.coldDrainState = .pending
        throw error
      }
      // Settle state before any waiter can resume on the actor.
      self.coldDrainState = .done
      return generation
    }
    coldDrainState = .running(task)
    return try await task.value
  }

  /// The daemon replies to a barrier without decoding its inert keyboard payload.
  private func performColdDrain() async throws {
    let barrier = try encode(
      messageType: "IndigoKeyboardButtonEvent",
      payload: IndigoKeyboardButtonEvent(usageCode: 0, state: .up),
      isBarrier: true)
    do {
      try await clock.awaitBarrierReply(connection, barrier)
    } catch is DTUHIDDrainTimeout {
      return try await clock.sleep(DTUHIDTiming.fallbackDrain)
    }
    try await clock.sleep(DTUHIDTiming.replyTail)
  }

}
