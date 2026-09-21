/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@preconcurrency import XPC

// SAFETY: All mutable state and transport calls are confined to queue.
// patternlint-disable-next-line unchecked-sendable
final class SimulatorCoreDeviceRequest<Response: Sendable>: @unchecked Sendable {
  private let transport: any SimulatorCoreDeviceTransport
  private let queue: DispatchQueue
  private let timeout: DispatchTimeInterval
  private var continuation: CheckedContinuation<Response, Error>?
  private var result: Result<Response, Error>?

  init(transport: any SimulatorCoreDeviceTransport, queue: DispatchQueue, timeout: DispatchTimeInterval = .seconds(5)) {
    self.transport = transport
    self.queue = queue
    self.timeout = timeout
  }

  func read(_ request: xpc_object_t, decode: @escaping @Sendable (xpc_object_t) throws -> Response) async throws -> Response {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        queue.async { [self] in
          if let result = self.result {
            continuation.resume(with: result)
            return
          }
          self.continuation = continuation
          self.transport.start(
            request: request,
            event: { [weak self] event in
              if xpc_get_type(event) == XPC_TYPE_ERROR {
                self?.finish(.failure(SimulatorCoreDeviceError.unavailable("Connection closed before reply")))
              }
            },
            reply: { [weak self] reply in
              guard let self, self.result == nil else { return }
              do { self.finish(.success(try decode(reply))) } catch { self.finish(.failure(error)) }
            })
          self.queue.asyncAfter(deadline: .now() + self.timeout) { [weak self] in
            self?.finish(.failure(SimulatorCoreDeviceError.unavailable("Response timed out")))
          }
        }
      }
    } onCancel: {
      self.queue.async { self.finish(.failure(CancellationError())) }
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
