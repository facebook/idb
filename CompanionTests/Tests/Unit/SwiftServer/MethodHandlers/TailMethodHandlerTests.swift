/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import FBControlCore
import Foundation
import GRPCCore
import IDBGRPCSwift
import Testing

private final class ScriptedTail: TailOperation, @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  var wasCancelled: Bool { lock.withLock { cancelled } }

  func cancel() async throws {
    lock.withLock { cancelled = true }
  }
}

private struct StreamEnded: Error {}

private struct SendFailed: Error {}

private final class ForwardedData: @unchecked Sendable {
  private let lock = NSLock()
  private var sent: [Data] = []
  private var _consumer: (any DataConsumer)?

  var all: [Data] { lock.withLock { sent } }
  var consumer: any DataConsumer { lock.withLock { _consumer! } }

  func record(_ data: Data) { lock.withLock { sent.append(data) } }
  func capture(_ consumer: any DataConsumer) { lock.withLock { _consumer = consumer } }
}

@Suite
struct TailMethodHandlerTests {

  @Test
  func aStopCancelsTheTail() async throws {
    let tail = ScriptedTail()
    try await TailMethodHandler.tail(send: { _ in }, awaitStop: {}, start: { _ in tail })
    #expect(tail.wasCancelled)
  }

  @Test
  func aStreamEndingWithoutAStopFailsTheCall() async throws {
    let tail = ScriptedTail()
    do {
      try await TailMethodHandler.tail(send: { _ in }, awaitStop: { throw StreamEnded() }, start: { _ in tail })
      Issue.record("the call outlived its request stream")
    } catch is StreamEnded {}
    #expect(tail.wasCancelled)
  }

  @Test
  func eachChunkIsForwardedInOrder() async throws {
    let forwarded = ForwardedData()
    try await TailMethodHandler.tail(
      send: { forwarded.record($0.data) },
      awaitStop: { forwarded.consumer.consumeEndOfFile() },
      start: { consumer in
        forwarded.capture(consumer)
        consumer.consumeData(Data("a".utf8))
        consumer.consumeData(Data("b".utf8))
        return ScriptedTail()
      })
    #expect(forwarded.all == [Data("a".utf8), Data("b".utf8)])
  }

  @Test
  func aFailedSendStopsForwarding() async throws {
    let attempted = ForwardedData()
    try await TailMethodHandler.tail(
      send: {
        attempted.record($0.data)
        throw SendFailed()
      },
      awaitStop: { attempted.consumer.consumeEndOfFile() },
      start: { consumer in
        attempted.capture(consumer)
        consumer.consumeData(Data("a".utf8))
        consumer.consumeData(Data("b".utf8))
        return ScriptedTail()
      })
    #expect(attempted.all == [Data("a".utf8)])
  }

  @Test
  func dataConsumedAfterTheStopIsNotForwarded() async throws {
    let forwarded = ForwardedData()
    try await TailMethodHandler.tail(
      send: { forwarded.record($0.data) },
      awaitStop: {},
      start: { consumer in
        forwarded.capture(consumer)
        return ScriptedTail()
      })
    forwarded.consumer.consumeData(Data("late".utf8))
    forwarded.consumer.consumeEndOfFile()
    #expect(forwarded.all == [])
  }
}
