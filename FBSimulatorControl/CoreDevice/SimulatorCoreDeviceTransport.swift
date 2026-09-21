/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@preconcurrency import XPC

protocol SimulatorCoreDeviceTransport: Sendable {
  func start(
    request: xpc_object_t,
    event: @escaping @Sendable (xpc_object_t) -> Void,
    reply: @escaping @Sendable (xpc_object_t) -> Void)
  func acknowledge(_ event: xpc_object_t, cancelling: Bool)
  func cancel()
}

// SAFETY: The owning request session accesses the connection and started flag only on queue.
// patternlint-disable-next-line unchecked-sendable
final class SimulatorCoreDeviceXPCTransport: SimulatorCoreDeviceTransport, @unchecked Sendable {
  private let connection: xpc_connection_t
  private let queue: DispatchQueue
  private var started = false

  init(simulator: Simulator, service: String, queue: DispatchQueue) throws {
    self.queue = queue
    connection = try SimulatorCoreDevice.connect(simulator: simulator, service: service)
    xpc_connection_set_target_queue(connection, queue)
  }

  func start(
    request: xpc_object_t,
    event: @escaping @Sendable (xpc_object_t) -> Void,
    reply: @escaping @Sendable (xpc_object_t) -> Void
  ) {
    dispatchPrecondition(condition: .onQueue(queue))
    started = true
    xpc_connection_set_event_handler(connection, event)
    xpc_connection_resume(connection)
    xpc_connection_send_message_with_reply(connection, request, queue, reply)
  }

  func acknowledge(_ event: xpc_object_t, cancelling: Bool) {
    dispatchPrecondition(condition: .onQueue(queue))
    guard xpc_get_type(event) == XPC_TYPE_DICTIONARY,
      let reply = xpc_dictionary_create_reply(event)
    else { return }
    xpc_dictionary_set_bool(reply, SimulatorCoreDevice.cancellationKey, cancelling)
    xpc_connection_send_message(connection, reply)
  }

  func cancel() {
    dispatchPrecondition(condition: .onQueue(queue))
    if !started {
      started = true
      xpc_connection_set_event_handler(connection) { _ in }
      xpc_connection_resume(connection)
    }
    xpc_connection_cancel(connection)
  }

}
