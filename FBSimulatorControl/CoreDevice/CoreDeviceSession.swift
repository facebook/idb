/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@preconcurrency import XPC

/// One CoreDevice request over one transport, bounded by a deadline and by task cancellation.
///
/// A request is either a `read`, one message answered by one reply, or a `stream`, one message that
/// the provider answers with pushed events until it is asked to stop and then with a final reply.
/// Either way the transport is cancelled once the session has its result, so a session is used once.
///
// SAFETY: All mutable state and transport calls are confined to queue, including cancellation.
// patternlint-disable-next-line unchecked-sendable
final class CoreDeviceSession<Response: Sendable>: @unchecked Sendable {
  private let transport: any SimulatorCoreDeviceTransport
  private let queue: DispatchQueue
  private let timeout: DispatchTimeInterval
  private var continuation: CheckedContinuation<Response, Error>?
  private var result: Result<Response, Error>?
  private var held: Response?

  init(transport: any SimulatorCoreDeviceTransport, queue: DispatchQueue, timeout: DispatchTimeInterval = .seconds(5)) {
    self.transport = transport
    self.queue = queue
    self.timeout = timeout
  }

  /// Sends `request` and decodes its one reply.
  func read(_ request: xpc_object_t, decode: @escaping @Sendable (xpc_object_t) throws -> Response) async throws -> Response {
    try await perform(
      request,
      event: { [weak self] event in
        if xpc_get_type(event) == XPC_TYPE_ERROR {
          self?.finish(.failure(SimulatorCoreDeviceError.unavailable("Connection closed before reply")))
        }
      },
      reply: { [weak self] reply in
        guard let self, self.result == nil else { return }
        do { self.finish(.success(try decode(reply))) } catch { self.finish(.failure(error)) }
      })
  }

  /// Sends `request` and reads the events the provider pushes back. Every event is acknowledged;
  /// once `sample` yields a value the acknowledgement asks the provider to stop, and the value is
  /// returned when the provider's final reply confirms it has. A final reply before any value is an
  /// error, as is a reply carrying a provider error.
  func stream(_ request: xpc_object_t, sample: @escaping @Sendable (xpc_object_t) throws -> Response?) async throws -> Response {
    try await perform(
      request,
      event: { [weak self] event in self?.handleStreamEvent(event, sample: sample) },
      reply: { [weak self] reply in self?.handleStreamReply(reply) })
  }

  private func perform(
    _ request: xpc_object_t,
    event: @escaping @Sendable (xpc_object_t) -> Void,
    reply: @escaping @Sendable (xpc_object_t) -> Void
  ) async throws -> Response {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        queue.async { [self] in
          if let result = self.result {
            continuation.resume(with: result)
            return
          }
          self.continuation = continuation
          self.transport.start(request: request, event: event, reply: reply)
          self.queue.asyncAfter(deadline: .now() + self.timeout) { [weak self] in
            self?.finish(.failure(SimulatorCoreDeviceError.timedOut))
          }
        }
      }
    } onCancel: {
      self.queue.async { self.finish(.failure(CancellationError())) }
    }
  }

  private func handleStreamEvent(_ event: xpc_object_t, sample: (xpc_object_t) throws -> Response?) {
    dispatchPrecondition(condition: .onQueue(queue))
    guard result == nil else { return }
    guard xpc_get_type(event) == XPC_TYPE_DICTIONARY else {
      finish(.failure(SimulatorCoreDeviceError.unavailable("Connection closed before the stream completed")))
      return
    }
    do {
      if held == nil {
        held = try sample(event)
      }
      transport.acknowledge(event, cancelling: held != nil)
    } catch {
      finish(.failure(error))
    }
  }

  private func handleStreamReply(_ reply: xpc_object_t) {
    dispatchPrecondition(condition: .onQueue(queue))
    guard result == nil else { return }
    do {
      _ = try CoreDeviceReply.output(of: reply)
      guard let held else { throw SimulatorCoreDeviceError.unavailable("Stream ended without a sample") }
      finish(.success(held))
    } catch {
      finish(.failure(error))
    }
  }

  private func finish(_ result: Result<Response, Error>) {
    dispatchPrecondition(condition: .onQueue(queue))
    guard self.result == nil else { return }
    self.result = result
    transport.cancel()
    continuation?.resume(with: result)
    continuation = nil
  }
}
