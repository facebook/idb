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
import XPC
import os

/// The waits `SimulatorDTUHIDConnection` performs around the events it sends.
enum DTUHIDTiming {

  /// Time allowed for a warm connection to dispatch events before disconnecting.
  static let drain = Duration.milliseconds(80)

  /// Time allowed for device-open and dispatch after the barrier reply signals peer activation.
  static let replyTail = Duration.milliseconds(200)

  /// Deadline for the connect-time liveness reply. Generous because this is the send that
  /// demand-launches `dtuhidd`, so it pays for the daemon's cold start.
  static let livenessTimeout = DispatchTimeInterval.seconds(4)

  /// Wait between liveness attempts. `dtuhidd` declares a 10s `minimum runtime`, so launchd
  /// throttles the respawn of one that aborted before reaching it; retrying sooner only re-reads
  /// the same throttled job.
  static let livenessRetryBackoff = Duration.seconds(4)

  /// Liveness attempts before the transport is reported unreachable and the caller falls back.
  ///
  /// Sized from a measured recovery: a daemon that aborted repeatedly through a slow boot answered
  /// roughly 19s after the boot finished, launchd's exponential respawn throttle being what that
  /// wait is made of rather than the daemon's own start-up. At `livenessTimeout + livenessRetryBackoff`
  /// per attempt that took three, so three is the floor, not the budget.
  static let livenessAttempts = 5
}

/// What came back from the liveness barrier. The reply object itself is read on the XPC queue and not carried
/// out, so the answer crosses isolation as plain values.
private struct XPCReply: Sendable {
  /// Set when XPC answered on the peer's behalf rather than the peer answering, which means no
  /// daemon took the message.
  let errorDescription: String?
}

/// Sends `message` and resolves with whichever comes first, the XPC reply or `timeout`.
private func awaitXPCReply(
  _ connection: xpc_connection_t,
  _ message: xpc_object_t,
  timeout: DispatchTimeInterval
) async throws -> XPCReply {
  try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<XPCReply, Error>) in
    // SAFETY: The lock serializes the reply and timeout callbacks.
    // patternlint-disable-next-line unchecked-sendable
    final class FirstAnswer: @unchecked Sendable {
      private let lock = NSLock()
      private var pending = true

      /// True for exactly one caller, which owns resuming the continuation.
      func claim() -> Bool {
        lock.withLock {
          defer { pending = false }
          return pending
        }
      }
    }
    let answer = FirstAnswer()
    xpc_connection_send_message_with_reply(
      connection, message, DispatchQueue.global(qos: .userInitiated)
    ) { reply in
      var errorDescription: String?
      if xpc_get_type(reply) == XPC_TYPE_ERROR {
        errorDescription =
          xpc_dictionary_get_string(reply, XPC_ERROR_KEY_DESCRIPTION)
          .map { String(cString: $0) } ?? "unknown XPC error"
      }
      if answer.claim() {
        continuation.resume(returning: XPCReply(errorDescription: errorDescription))
      }
    }
    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
      if answer.claim() {
        continuation.resume(throwing: DTUHIDLivenessFailure.timedOut)
      }
    }
  }
}

/// Injectable waits for the DTUHID transport.
struct DTUHIDDrainClock: Sendable {
  let sleep: @Sendable (Duration) async throws -> Void
  /// An XPC error reply fails rather than resolving: the probe asks whether there is a peer at all,
  /// so XPC's own answer is the negative result.
  let awaitLivenessReply: @Sendable (xpc_connection_t, xpc_object_t) async throws -> Void

  init(
    sleep: @escaping @Sendable (Duration) async throws -> Void,
    awaitLivenessReply: @escaping @Sendable (xpc_connection_t, xpc_object_t) async throws -> Void = { _, _ in }
  ) {
    self.sleep = sleep
    self.awaitLivenessReply = awaitLivenessReply
  }

  static let live = DTUHIDDrainClock(
    sleep: { try await Task.sleep(for: $0) },
    awaitLivenessReply: { connection, message in
      let reply = try await awaitXPCReply(connection, message, timeout: DTUHIDTiming.livenessTimeout)
      if let errorDescription = reply.errorDescription {
        throw DTUHIDLivenessFailure.peerUnavailable(errorDescription)
      }
    })
}

/// Nothing live was found behind a DTUHID connection at connect time.
enum DTUHIDLivenessFailure: Error, CustomStringConvertible {
  /// The probe went unanswered. `dtuhidd` is throttled, crash-looping, or wedged.
  case timedOut
  /// XPC replied on the peer's behalf, so the daemon is not running and could not be launched.
  case peerUnavailable(String)

  var description: String {
    switch self {
    case .timedOut:
      return "no reply within \(DTUHIDTiming.livenessTimeout)"
    case let .peerUnavailable(detail):
      return detail
    }
  }
}

/**
 One host XPC connection to a `dtuhidd` HID service, and the drain that lets events sent on it reach the
 guest before it is torn down. Knows nothing of what the events mean: the digitizer and vendor-defined
 transports each encode their own payloads and write them here.

 A class rather than an actor so `write` is synchronous: a transport assigning order-dependent state
 (a contact's start/position/end) writes before it next suspends, which a hop onto another actor
 would not guarantee. The XPC connection is thread-safe, and the send counters are behind a lock.
 */
final class SimulatorDTUHIDConnection: Sendable {

  // SAFETY: XPC connections support concurrent sending and cancellation.
  // patternlint-disable-next-line swift-nonisolated-unsafe
  nonisolated(unsafe) private let connection: xpc_connection_t
  let serviceName: String
  private let clock: DTUHIDDrainClock
  // A drain claims a snapshot of the send count; later sends remain outstanding.
  private let generations = OSAllocatedUnfairLock(initialState: (sent: 0, drained: 0))

  /// Connects to the simulator's DTUHID service, confirming a live `dtuhidd` answers before the
  /// connection is handed out.
  ///
  /// Retried, because the daemon's startup races the guest's. `dtuhidd` is demand-launched early in
  /// boot and asks CoreAnimation for the display list, which aborts the process outright when no
  /// display is up yet — reliably so on a boot slow enough to still be `WaitingOnBackboard`. What is
  /// left behind is a job launchd will respawn but has throttled, for which the service lookup below
  /// still yields a port and every send is then silently discarded. The window is seconds wide and
  /// closes once the boot settles, so a backed-off retry recovers the full transport, keyboard
  /// included, where giving up would cost the keyboard for the lifetime of the boot.
  static func connect(using connector: SimulatorXPCConnector, serviceName: String) async throws -> SimulatorDTUHIDConnection {
    let logger = ControlCoreGlobalConfiguration.defaultLogger
    var lastFailure: Error?
    for attempt in 1...DTUHIDTiming.livenessAttempts {
      do {
        return try await connected(using: connector, serviceName: serviceName)
      } catch let error as SimulatorHIDError where !error.isTransientDTUHIDFailure {
        // A toolchain that has no DTUHID at all will not grow one by being asked again.
        throw error
      } catch {
        lastFailure = error
        logger.log(
          "dtuhidd did not answer the liveness probe (attempt \(attempt) of \(DTUHIDTiming.livenessAttempts)): \(error)")
        guard attempt < DTUHIDTiming.livenessAttempts else {
          break
        }
        try await Task.sleep(for: DTUHIDTiming.livenessRetryBackoff)
      }
    }
    throw SimulatorHIDError.dtuhidUnresponsive(
      attempts: DTUHIDTiming.livenessAttempts, underlying: lastFailure)
  }

  /// One attempt: look the service up, connect, and prove a daemon is behind it.
  ///
  /// The lookup belongs to the attempt rather than preceding the loop. It fails while the job is
  /// mid-respawn, which is exactly the state being retried out of, so hoisting it turns the most
  /// recoverable moment into a terminal one.
  private static func connected(using connector: SimulatorXPCConnector, serviceName: String) async throws -> SimulatorDTUHIDConnection {
    let connection = SimulatorDTUHIDConnection(
      connection: try xpcConnection(using: connector, serviceName: serviceName),
      serviceName: serviceName)
    do {
      try await connection.confirmLiveness()
    } catch {
      connection.disconnect()
      throw error
    }
    return connection
  }

  /// A resumed host XPC connection to the requested guest HID service. Says nothing about whether
  /// `dtuhidd` is able to run — launchd vends the port for a demand-launched job either way.
  private static func xpcConnection(using connector: SimulatorXPCConnector, serviceName: String) throws -> xpc_connection_t {
    let connection: xpc_connection_t
    do {
      connection = try connector.connect(serviceName)
    } catch let error as SimulatorXPCConnectionError {
      throw SimulatorHIDError(dtuhidConnection: error)
    }
    xpc_connection_set_event_handler(connection) { _ in }
    xpc_connection_resume(connection)
    return connection
  }

  init(connection: xpc_connection_t, serviceName: String, clock: DTUHIDDrainClock = .live) {
    self.connection = connection
    self.serviceName = serviceName
    self.clock = clock
  }

  /// Round-trips a barrier to establish that a `dtuhidd` is behind the connection and has activated.
  ///
  /// The only observation available: every step of building the connection succeeds against a
  /// daemon that cannot run, and a send to one reports no error, so an unanswered probe is what
  /// separates a working transport from a black hole.
  ///
  /// A reply also means the peer activated. Paying the device-open tail here, before the connection
  /// is handed out, is what lets every later drain be the short warm one.
  func confirmLiveness() async throws {
    try await clock.awaitLivenessReply(connection, barrierMessage())
    try await clock.sleep(DTUHIDTiming.replyTail)
  }

  func disconnect() {
    xpc_connection_cancel(connection)
  }

  // MARK: - Sending

  /// Wraps `payload` in a `DTUHIDMessage` and serializes it to the `xpc_object_t` `dtuhidd` decodes.
  func encode(messageType: String, payload: some Encodable, isBarrier: Bool = false) throws -> xpc_object_t {
    let message = DTUHIDMessage(
      messageType: messageType,
      featureIdentifier: serviceName,
      isBarrier: isBarrier,
      payload: payload)
    return try XPCEncoder().encode(message)
  }

  /// Encodes `payload` and hands it to XPC before returning, marking it outstanding for `flush()`.
  func write(messageType: String, payload: some Encodable) throws {
    let object = try encode(messageType: messageType, payload: payload)
    generations.withLock { $0.sent += 1 }
    xpc_connection_send_message(connection, object)
  }

  /// Resolves once XPC has sent everything written before this call. Does not wait for the daemon to
  /// consume it — that is `flush()`'s job, run once per gesture rather than per primitive.
  func awaitSendBarrier() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      xpc_connection_send_barrier(connection) {
        continuation.resume()
      }
    }
  }

  /// `write` then `awaitSendBarrier`, for a sender with no order-dependent state to guard.
  func send(messageType: String, payload: some Encodable) async throws {
    try write(messageType: messageType, payload: payload)
    await awaitSendBarrier()
  }

  /// Allows time for events sent before this call to reach the guest before disconnecting.
  /// Returns immediately when no sends are outstanding.
  func flush() async throws {
    let generation = generations.withLock { $0.sent }
    guard generation > generations.withLock({ $0.drained }) else {
      return
    }
    try await clock.sleep(DTUHIDTiming.drain)
    generations.withLock { $0.drained = max($0.drained, generation) }
  }

  /// A barrier carrying usage `0` — "no event indicated" — so the daemon answers without the guest
  /// seeing a keypress.
  private func barrierMessage() throws -> xpc_object_t {
    try encode(
      messageType: "IndigoKeyboardButtonEvent",
      payload: IndigoKeyboardButtonEvent(usageCode: 0, state: .up),
      isBarrier: true)
  }
}
