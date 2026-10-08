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

/// A pipe whose reader or writer never finishes hangs rather than failing, so each test is capped.
@Suite(.timeLimit(.minutes(1)))
struct BytePipeTests {

  private static func readAll(_ pipe: BytePipe) async throws -> Data {
    try await pipe.reading { source in
      let source = HandedOver(source)
      return try await offCooperativePool { try source.value.readAll() }.get()
    }
  }

  @Test
  func aPipeOfDataReadsItThenEnds() async throws {
    #expect(try await Self.readAll(BytePipe(Data("hello".utf8))) == Data("hello".utf8))
  }

  @Test
  func writesMadeWhileReadingArriveInOrderUntilFinished() async throws {
    let pipe = BytePipe()
    async let read = Self.readAll(pipe)

    for chunk in ["first ", "second ", "third"] {
      try await pipe.input.writeAndWait(Data(chunk.utf8))
    }
    pipe.input.finish()

    #expect(try await read == Data("first second third".utf8))
  }

  @Test
  func aWriterWhoseReaderStoppedEarlyFailsRatherThanBlocking() async throws {
    let pipe = BytePipe()

    // Started once the reader is attached, since a write before then is held rather than awaited,
    // and well past any pipe buffer, so it is still waiting when the reader stops.
    let (head, write) = try await pipe.reading { source in
      let write = Task { try await pipe.input.writeAndWait(Data(count: 4 * 1024 * 1024)) }
      let source = HandedOver(source)
      let head = try await offCooperativePool { () throws -> Int in
        var buffer = [UInt8](repeating: 0, count: 16)
        return try buffer.withUnsafeMutableBytes { try source.value.read(into: $0) }
      }.get()
      return (head, write)
    }

    #expect(head > 0)
    await #expect(throws: SubprocessError.self) {
      try await write.value
    }
  }

  @Test
  func aPipeIsReadOnce() async throws {
    let pipe = BytePipe(Data("once".utf8))
    _ = try await Self.readAll(pipe)

    await #expect(throws: SubprocessError.self) {
      _ = try await Self.readAll(pipe)
    }
  }
}
