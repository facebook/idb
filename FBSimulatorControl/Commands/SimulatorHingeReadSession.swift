/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@preconcurrency import XPC

protocol HingeReadTransport: Sendable {
  func start(
    request: xpc_object_t,
    event: @escaping @Sendable (xpc_object_t) -> Void,
    reply: @escaping @Sendable (xpc_object_t) -> Void)
  func acknowledge(_ event: xpc_object_t, cancelling: Bool)
  func cancel()
}

// SAFETY: All mutable state and transport calls are confined to queue, including cancellation.
// patternlint-disable-next-line unchecked-sendable
final class SimulatorHingeReadSession: @unchecked Sendable {
  private let transport: any HingeReadTransport
  private let queue: DispatchQueue
  private let timeout: DispatchTimeInterval
  private let now: @Sendable () -> TimeInterval
  private let channel: UUID
  private var continuation: CheckedContinuation<SimulatorHingeAngle, Error>?
  private var result: Result<SimulatorHingeAngle, Error>?
  private var selectedAngle: SimulatorHingeAngle?
  private var startedAt: TimeInterval = 0

  init(
    transport: any HingeReadTransport,
    queue: DispatchQueue,
    timeout: DispatchTimeInterval = .seconds(5),
    channel: UUID = UUID(),
    now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
  ) {
    self.transport = transport
    self.queue = queue
    self.timeout = timeout
    self.channel = channel
    self.now = now
  }

  func read(deviceID: String, version: String) async throws -> SimulatorHingeAngle {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        queue.async { [self] in
          if let result = self.result {
            continuation.resume(with: result)
            return
          }
          self.continuation = continuation
          do {
            let request = try SimulatorHingeProtocol.request(deviceID: deviceID, version: version, channel: self.channel)
            self.startedAt = self.now()
            self.transport.start(
              request: request,
              event: { [weak self] event in self?.handleEvent(event) },
              reply: { [weak self] reply in self?.handleReply(reply) })
            self.queue.asyncAfter(deadline: .now() + self.timeout) { [weak self] in
              self?.finish(.failure(SimulatorHingeReadError.timedOut))
            }
          } catch {
            self.finish(.failure(error))
          }
        }
      }
    } onCancel: {
      self.queue.async { self.finish(.failure(CancellationError())) }
    }
  }

  private func handleEvent(_ event: xpc_object_t) {
    dispatchPrecondition(condition: .onQueue(queue))
    guard result == nil else { return }
    guard xpc_get_type(event) == XPC_TYPE_DICTIONARY else {
      finish(.failure(SimulatorHingeReadError.unavailable("Motion connection closed")))
      return
    }
    do {
      if selectedAngle == nil {
        selectedAngle = try SimulatorHingeProtocol.sample(event, channel: channel, notBefore: startedAt, now: now())
      }
      transport.acknowledge(event, cancelling: selectedAngle != nil)
    } catch {
      finish(.failure(error))
    }
  }

  private func handleReply(_ reply: xpc_object_t) {
    dispatchPrecondition(condition: .onQueue(queue))
    guard result == nil else { return }
    do {
      try SimulatorHingeProtocol.checkReply(reply)
      guard let selectedAngle else { throw SimulatorHingeReadError.endedWithoutSample }
      finish(.success(selectedAngle))
    } catch {
      finish(.failure(error))
    }
  }

  private func finish(_ result: Result<SimulatorHingeAngle, Error>) {
    dispatchPrecondition(condition: .onQueue(queue))
    guard self.result == nil else { return }
    self.result = result
    transport.cancel()
    continuation?.resume(with: result)
    continuation = nil
  }
}
