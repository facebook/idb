/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@preconcurrency import XPC

/// One CoreDevice request over one channel, bounded by a deadline and by task cancellation.
///
/// A request is either a `read`, one message answered by one reply, or a `stream`, one message that
/// the provider answers with pushed events until it is asked to stop and then with a final reply.
/// Either way the channel is cancelled once the session has its result, so a session is used once.
///
// SAFETY: All mutable state and channel callbacks are confined to the channel's queue, including cancellation.
// patternlint-disable-next-line unchecked-sendable
final class CoreDeviceSession<Response: Sendable>: @unchecked Sendable {
  private let channel: SimulatorXPCChannel
  private let queue: DispatchQueue
  private let timeout: DispatchTimeInterval
  private var held: Response?
  private var finished = false

  init(channel: SimulatorXPCChannel, timeout: DispatchTimeInterval = .seconds(5)) {
    self.channel = channel
    self.queue = channel.queue
    self.timeout = timeout
  }

  /// Sends `request` and decodes its one reply.
  func read(_ request: xpc_object_t, decode: @escaping @Sendable (xpc_object_t) throws -> Response) async throws -> Response {
    defer { channel.cancel() }
    channel.activate { _ in }
    let reply: xpc_object_t
    do {
      reply = try await channel.request(request, timeout: timeout)
    } catch let error as SimulatorXPCError {
      throw SimulatorCoreDeviceError(channel: error)
    }
    return try decode(reply)
  }

  /// Sends `request` and reads the events the provider pushes back. Every event is acknowledged;
  /// once `sample` yields a value the acknowledgement asks the provider to stop, and the value is
  /// returned when the provider's final reply confirms it has. A final reply before any value is an
  /// error, as is a reply carrying a provider error.
  func stream(_ request: xpc_object_t, sample: @escaping @Sendable (xpc_object_t) throws -> Response?) async throws -> Response {
    defer { channel.cancel() }
    do {
      return try await channel.firstAnswer(timeout: timeout) { answer in
        channel.activate { [weak self] event in self?.handleStreamEvent(event, sample: sample, answer: answer) }
        channel.request(request) { [weak self] reply in self?.handleStreamReply(reply, answer: answer) }
      }
    } catch let error as SimulatorXPCError {
      throw SimulatorCoreDeviceError(channel: error)
    }
  }

  private func handleStreamEvent(_ event: SimulatorXPCEvent, sample: (xpc_object_t) throws -> Response?, answer: FirstAnswer<Response>) {
    dispatchPrecondition(condition: .onQueue(queue))
    guard !finished else { return }
    guard case let .message(event) = event else {
      finish(.failure(SimulatorCoreDeviceError.unavailable("Connection closed before the stream completed")), answer)
      return
    }
    do {
      if held == nil {
        held = try sample(event)
      }
      let cancelling = held != nil
      channel.reply(to: event) { xpc_dictionary_set_bool($0, SimulatorCoreDevice.cancellationKey, cancelling) }
    } catch {
      finish(.failure(error), answer)
    }
  }

  private func handleStreamReply(_ reply: Result<xpc_object_t, SimulatorXPCError>, answer: FirstAnswer<Response>) {
    dispatchPrecondition(condition: .onQueue(queue))
    guard !finished else { return }
    finish(
      Result {
        try CoreDeviceReply.validate(reply.get())
        guard let held else { throw SimulatorCoreDeviceError.unavailable("Stream ended without a sample") }
        return held
      }, answer)
  }

  /// Stops acknowledging events once the stream has its result. The deadline and cancellation
  /// resolve `answer` without coming through here; `stream` cancels the channel either way.
  private func finish(_ result: Result<Response, Error>, _ answer: FirstAnswer<Response>) {
    dispatchPrecondition(condition: .onQueue(queue))
    finished = true
    answer.resolve(result)
  }
}
