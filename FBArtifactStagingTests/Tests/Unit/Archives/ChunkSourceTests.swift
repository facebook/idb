/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBArtifactStaging
@testable import FBControlCore
import Foundation
import Testing
import os

/// `ChunkSource`, the bridge from an asynchronous producer to a synchronous reader, held to the `ByteSource` contract
/// and to its own: a bounded buffer, the producer's failure in-band, and a reader that can stop early.
@Suite
struct ChunkSourceTests {

  private struct ProducerFailed: Error {}

  private static func chunks(_ count: Int, size: Int = 64 << 10) -> [Data] {
    (0..<count).map { index in Data(repeating: UInt8(truncatingIfNeeded: index), count: size) }
  }

  /// Reads `source` to its end on a thread of its own, `size` bytes at a time, pausing after each read.
  private static func readAll(_ source: ChunkSource, size: Int = 64 << 10, pause: TimeInterval = 0, after each: @escaping @Sendable () -> Void = {}) async -> Result<Data, any Error> {
    let source = HandedOver(source)
    return await offCooperativePool {
      var contents = Data()
      var buffer = [UInt8](repeating: 0, count: size)
      while case let count = try buffer.withUnsafeMutableBytes({ try source.value.read(into: $0) }), count > 0 {
        contents.append(contentsOf: buffer[..<count])
        each()
        if pause > 0 {
          Thread.sleep(forTimeInterval: pause)
        }
      }
      return contents
    }
  }

  @Test(arguments: [1, 7, 4096, 1 << 16])
  func pumpedChunksArriveInOrderThenTheInputEnds(bufferSize: Int) async throws {
    let chunks = Self.chunks(20, size: 10_000)
    let source = ChunkSource(capacity: 32_000)
    async let pumped: Void = source.pump(
      AsyncThrowingStream { continuation in
        chunks.forEach { continuation.yield($0) }
        continuation.finish()
      }, after: Data("head".utf8))
    let contents = try await Self.readAll(source, size: bufferSize).get()
    try await pumped
    #expect(contents == Data("head".utf8) + chunks.reduce(Data(), +))
    var buffer = [UInt8](repeating: 0, count: 8)
    #expect(try buffer.withUnsafeMutableBytes { try source.read(into: $0) } == 0)
  }

  /// Both what waits to be read and what the source holds on to, read or not, since a chunk kept after it was read
  /// costs memory as much as one still waiting.
  @Test
  func whatIsWaitingNeverExceedsTheCapacityAndOneChunk() async throws {
    let capacity = 256 << 10
    let chunkSize = 64 << 10
    let source = ChunkSource(capacity: capacity)
    let mostWaiting = OSAllocatedUnfairLock(initialState: 0)
    let chunks = Self.chunks(64, size: chunkSize)
    async let pumped: Void = source.pump(
      AsyncThrowingStream { continuation in
        chunks.forEach { continuation.yield($0) }
        continuation.finish()
      })
    let mostHeld = OSAllocatedUnfairLock(initialState: 0)
    _ = try await Self.readAll(source, size: 16 << 10, pause: 0.001) {
      let (waiting, held) = (source.waitingBytes, source.heldBytes)
      mostWaiting.withLock { $0 = max($0, waiting) }
      mostHeld.withLock { $0 = max($0, held) }
    }.get()
    try await pumped
    #expect(mostWaiting.withLock { $0 } <= capacity + chunkSize)
    #expect(mostHeld.withLock { $0 } <= capacity + 2 * chunkSize, "held at most \(mostHeld.withLock { $0 }) bytes")
    #expect(mostWaiting.withLock { $0 } > 0)
  }

  @Test
  func theProducersFailureReachesTheReaderAfterWhatItWrote() async throws {
    let source = ChunkSource()
    let pumped = Task {
      try await source.pump(
        AsyncThrowingStream { continuation in
          continuation.yield(Data("written".utf8))
          continuation.finish(throwing: ProducerFailed())
        })
    }
    var buffer = [UInt8](repeating: 0, count: 64)
    let count = try buffer.withUnsafeMutableBytes { try source.read(into: $0) }
    #expect(Data(buffer[..<count]) == Data("written".utf8))
    let failure = #expect(throws: ChunkSource.UpstreamFailure.self) {
      _ = try buffer.withUnsafeMutableBytes { try source.read(into: $0) }
    }
    #expect(failure?.underlying is ProducerFailed)
    await #expect(throws: ProducerFailed.self) { try await pumped.value }
  }

  @Test
  func aReaderThatStopsReleasesAProducerWaitingForRoom() async throws {
    let source = ChunkSource(capacity: 1024)
    let pumped = Task {
      try await source.pump(
        AsyncThrowingStream { continuation in
          Self.chunks(4, size: 1024).forEach { continuation.yield($0) }
          continuation.finish()
        })
    }
    while source.waitingBytes == 0 {
      try await Task.sleep(for: .milliseconds(10))
    }
    source.abandon()
    await #expect(throws: ChunkSource.ReaderClosed.self) { try await pumped.value }
    var buffer = [UInt8](repeating: 0, count: 64)
    #expect(try buffer.withUnsafeMutableBytes { try source.read(into: $0) } == 0)
  }

  @Test
  func aCancelledProducerFailsTheReader() async throws {
    let source = ChunkSource()
    let (chunks, producer) = AsyncThrowingStream.makeStream(of: Data.self)
    producer.yield(Data("first".utf8))
    let pumped = Task { try await source.pump(chunks) }
    var buffer = [UInt8](repeating: 0, count: 64)
    _ = try buffer.withUnsafeMutableBytes { try source.read(into: $0) }
    pumped.cancel()
    let reading = await Self.readAll(source)
    guard case .failure(let error) = reading, let failure = error as? ChunkSource.UpstreamFailure else {
      Issue.record("expected an upstream failure, got \(reading)")
      return
    }
    #expect(failure.underlying is CancellationError)
  }
}
