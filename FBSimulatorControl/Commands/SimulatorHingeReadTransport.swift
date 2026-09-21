/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import Darwin
import Foundation
@preconcurrency import XPC

// SAFETY: The owning hinge session accesses the connection and started flag only on queue.
// patternlint-disable-next-line unchecked-sendable
final class SimulatorHingeReadTransport: HingeReadTransport, @unchecked Sendable {
  private let connection: xpc_connection_t
  private let queue: DispatchQueue
  private var started = false

  init(simulator: Simulator, queue: DispatchQueue) throws {
    self.queue = queue
    connection = try Self.connect(simulator: simulator)
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
    xpc_dictionary_set_bool(reply, SimulatorHingeProtocol.cancellationKey, cancelling)
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

  private typealias EndpointFromPort = @convention(c) (mach_port_t, UInt64, UInt64) -> Unmanaged<AnyObject>?
  private typealias ConnectionFromEndpoint = @convention(c) (xpc_object_t) -> Unmanaged<AnyObject>?
  private typealias EnableSim2Host = @convention(c) (xpc_connection_t) -> Void

  private static func connect(simulator: Simulator) throws -> xpc_connection_t {
    guard let handle = dlopen(nil, RTLD_NOW) else { throw SimulatorHingeReadError.unavailable("XPC symbols") }
    defer { dlclose(handle) }
    guard
      let endpointFromPort = symbol(handle, "xpc_endpoint_create_mach_port_4sim", as: EndpointFromPort.self),
      let connectionFromEndpoint = symbol(handle, "xpc_connection_create_from_endpoint", as: ConnectionFromEndpoint.self),
      let enableSim2Host = symbol(handle, "xpc_connection_enable_sim2host_4sim", as: EnableSim2Host.self)
    else { throw SimulatorHingeReadError.unavailable("Simulator XPC symbols") }
    var error: NSError?
    let port = simulator.device.lookup(SimulatorHingeProtocol.service, error: &error)
    guard port != MACH_PORT_NULL else {
      throw SimulatorHingeReadError.unavailable(error?.localizedDescription ?? SimulatorHingeProtocol.service)
    }
    // Both Create functions return +1. The endpoint consumes the lookup's send right.
    guard let endpoint = endpointFromPort(port, 0, 0)?.takeRetainedValue() as? xpc_object_t,
      let connection = connectionFromEndpoint(endpoint)?.takeRetainedValue() as? xpc_connection_t
    else { throw SimulatorHingeReadError.unavailable("Simulator XPC connection") }
    enableSim2Host(connection)
    return connection
  }

  private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as type: T.Type) -> T? {
    guard let pointer = dlsym(handle, name) else { return nil }
    return unsafeBitCast(pointer, to: type)
  }
}
