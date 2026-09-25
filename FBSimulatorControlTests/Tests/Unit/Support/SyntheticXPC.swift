/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
@testable import FBSimulatorControl
import Foundation
@preconcurrency import XPC
import os

/// A simulator's guest services, replaced by in-process XPC listeners and vended through the same
/// `SimulatorXPCConnector` production uses. Traffic crosses real XPC, so replies are routed,
/// barriers order sends, and a peer going away arrives as the XPC error event it would in a guest.
///
/// A service nobody registered fails its lookup as CoreSimulator reports a service the runtime does
/// not vend. Until the simulator is booted every lookup fails, registered or not, with the same
/// `SimError` 405, as CoreSimulator's do.
final class SyntheticXPCServices: Sendable {
  static let unsupportedService = NSError(domain: "com.apple.CoreSimulator.SimError", code: 405)

  private let state = OSAllocatedUnfairLock(
    initialState: (peers: [String: SyntheticXPCPeer](), lookups: [String](), simulator: TargetState.booted))

  /// Registers `service`, answered by `respond`.
  @discardableResult
  func register(_ service: String, respond: @escaping SyntheticXPCPeer.Responder) -> SyntheticXPCPeer {
    let peer = SyntheticXPCPeer(service: service, respond: respond)
    state.withLock { $0.peers[service] = peer }
    return peer
  }

  /// Every service looked up, in order, including the ones that failed.
  var lookups: [String] {
    state.withLock { $0.lookups }
  }

  /// The simulator's state. Booted unless a test says otherwise. A boot finishes while the
  /// connector's `bootFinished` is awaited, so a test does not race the boot it starts.
  var simulatorState: TargetState {
    get { state.withLock { $0.simulator } }
    set { state.withLock { $0.simulator = newValue } }
  }

  var connector: SimulatorXPCConnector {
    SimulatorXPCConnector(
      state: { [self] in simulatorState },
      lookup: { [self] service in try lookup(service) },
      bootFinished: { [self] in
        state.withLock { state in
          if state.simulator == .booting { state.simulator = .booted }
        }
      })
  }

  private func lookup(_ service: String) throws -> xpc_connection_t {
    let (peer, simulator) = state.withLock { state in
      state.lookups.append(service)
      return (state.peers[service], state.simulator)
    }
    guard simulator == .booted else {
      throw SimulatorXPCConnectionError.lookupFailed(
        service: service,
        underlying: NSError(
          domain: Self.unsupportedService.domain, code: Self.unsupportedService.code,
          userInfo: [NSLocalizedDescriptionKey: "Unable to lookup in current state: \(simulator.stateString.rawValue)"]))
    }
    guard let peer else {
      throw SimulatorXPCConnectionError.lookupFailed(service: service, underlying: Self.unsupportedService)
    }
    return peer.connect()
  }

  /// A channel to `service`, built through `connector` as production builds one.
  func channel(to service: String, queue: DispatchQueue = DispatchQueue(label: "com.facebook.FBSimulatorControlTests.synthetic-xpc.client")) throws -> SimulatorXPCChannel {
    SimulatorXPCChannel(connection: try connector.connect(service), queue: queue)
  }
}

/// One synthetic guest service: an anonymous XPC listener that records every message it receives, in
/// order, and answers each through its responder.
///
// SAFETY: All mutable state, and every responder call, is confined to queue.
// patternlint-disable-next-line unchecked-sendable
final class SyntheticXPCPeer: @unchecked Sendable {
  typealias Responder = @Sendable (SyntheticXPCRequest) -> Void

  let service: String
  fileprivate let queue: DispatchQueue
  private let listener: xpc_connection_t
  private let respond: Responder
  private var live: [xpc_connection_t] = []
  private var accepted = 0
  private var closedByClient = 0
  private var messages: [xpc_object_t] = []
  private var waiters: [UUID: (ready: () -> Bool, continuation: CheckedContinuation<Void, Never>)] = [:]

  fileprivate init(service: String, respond: @escaping Responder) {
    self.service = service
    self.respond = respond
    queue = DispatchQueue(label: "com.facebook.FBSimulatorControlTests.synthetic-xpc.\(service)")
    listener = xpc_connection_create(nil, queue)
    xpc_connection_set_event_handler(listener) { [weak self] object in
      guard let self, xpc_get_type(object) == XPC_TYPE_CONNECTION else { return }
      self.accept(object)
    }
    xpc_connection_resume(listener)
  }

  deinit {
    for connection in live { xpc_connection_cancel(connection) }
    xpc_connection_cancel(listener)
  }

  fileprivate func connect() -> xpc_connection_t {
    xpc_connection_create_from_endpoint(xpc_endpoint_create(listener))
  }

  /// A channel straight to this service, for a test that is not exercising the lookup.
  func channel(queue: DispatchQueue = DispatchQueue(label: "com.facebook.FBSimulatorControlTests.synthetic-xpc.client")) -> SimulatorXPCChannel {
    SimulatorXPCChannel(connection: connect(), queue: queue)
  }

  /// How many client connections have reached the service.
  var connections: Int {
    queue.sync { accepted }
  }

  /// How many client connections the client has cancelled, as opposed to the peer dropping them.
  var closed: Int {
    queue.sync { closedByClient }
  }

  /// Everything received so far.
  var received: [xpc_object_t] {
    queue.sync { messages }
  }

  /// Resolves once at least `count` messages have been received. One-way sends resolve at the
  /// client before the peer reads them, so a test waits here rather than reading `received`.
  func received(atLeast count: Int) async -> [xpc_object_t] {
    await wait { $0.messages.count >= count }
    return received
  }

  /// Resolves once the client has cancelled at least `count` connections, which reaches the peer
  /// after the client's call returns.
  func closed(atLeast count: Int) async -> Int {
    await wait { $0.closedByClient >= count }
    return closed
  }

  /// Resolves when `ready` holds, or after a deadline so that a test fails on its assertions rather
  /// than hanging.
  private func wait(until ready: @escaping @Sendable (SyntheticXPCPeer) -> Bool) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      queue.async { [self] in
        guard !ready(self) else { return continuation.resume() }
        let id = UUID()
        waiters[id] = ({ ready(self) }, continuation)
        queue.asyncAfter(deadline: .now() + 5) { [self] in
          waiters.removeValue(forKey: id)?.continuation.resume()
        }
      }
    }
  }

  private func resolveWaiters() {
    for (id, waiter) in waiters where waiter.ready() {
      waiters.removeValue(forKey: id)
      waiter.continuation.resume()
    }
  }

  /// Drops every client connection, as a guest daemon that exits does. Clients see
  /// `XPC_ERROR_CONNECTION_INTERRUPTED`, and their next send reaches the service again.
  func interrupt() {
    queue.sync {
      for connection in live { drop(connection) }
    }
  }

  fileprivate func drop(_ connection: xpc_connection_t) {
    dispatchPrecondition(condition: .onQueue(queue))
    live.removeAll { $0 === connection }
    xpc_connection_cancel(connection)
  }

  /// Removes the service for good. Clients see `XPC_ERROR_CONNECTION_INVALID`.
  func invalidate() {
    queue.sync {
      for connection in live { drop(connection) }
      xpc_connection_cancel(listener)
    }
  }

  private func accept(_ connection: xpc_connection_t) {
    dispatchPrecondition(condition: .onQueue(queue))
    live.append(connection)
    accepted += 1
    xpc_connection_set_target_queue(connection, queue)
    xpc_connection_set_event_handler(connection) { [weak self] message in
      guard let self else { return }
      guard xpc_get_type(message) == XPC_TYPE_DICTIONARY else {
        // The peer's own cancellations are removed from `live` first, so only the client's remain.
        if self.live.contains(where: { $0 === connection }) {
          self.live.removeAll { $0 === connection }
          self.closedByClient += 1
          self.resolveWaiters()
        }
        return
      }
      self.messages.append(message)
      self.resolveWaiters()
      self.respond(SyntheticXPCRequest(message: message, connection: connection, peer: self))
    }
    xpc_connection_resume(connection)
  }
}

/// One message as a synthetic service received it, and the ways the service can answer.
///
// SAFETY: Handed to responders on the peer's queue, and its acknowledgement callbacks run there too.
// patternlint-disable-next-line unchecked-sendable
struct SyntheticXPCRequest: @unchecked Sendable {
  let message: xpc_object_t
  fileprivate let connection: xpc_connection_t
  fileprivate let peer: SyntheticXPCPeer

  /// Answers the message with a reply carrying `values`'s entries. Ignored when the sender asked for
  /// no reply.
  func reply(_ values: xpc_object_t) {
    guard let reply = xpc_dictionary_create_reply(message) else { return }
    xpc_dictionary_apply(values) { key, value in
      xpc_dictionary_set_value(reply, key, value)
      return true
    }
    xpc_connection_send_message(connection, reply)
  }

  /// Pushes `event` to the client over the same connection, as a provider streams, and hands its
  /// acknowledgement to `acknowledged`.
  func push(_ event: xpc_object_t, acknowledged: @escaping @Sendable (xpc_object_t) -> Void) {
    xpc_connection_send_message_with_reply(connection, event, peer.queue, acknowledged)
  }

  /// Drops the connection this message arrived on, as a daemon exiting mid-request does. Call from
  /// the responder or an acknowledgement callback.
  func interrupt() {
    peer.drop(connection)
  }
}

extension SyntheticXPCPeer {
  /// Answers every message with `reply`.
  static func replying(_ reply: xpc_object_t) -> Responder {
    { $0.reply(reply) }
  }

  /// Receives every message and answers none.
  static let silent: Responder = { _ in }
}
