/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import Foundation
import GRPCCore
import IDBGRPCSwift
import Testing

/// Reads an install request stream into its header and payload.
@Suite
struct InstallRequestTests {

  private struct StreamFailed: Error {}

  private static func frames(_ requests: [Idb_InstallRequest], failing: Bool = false) -> RequestStreamReader<Idb_InstallRequest> {
    let source = AsyncThrowingStream<Idb_InstallRequest, any Error> { continuation in
      for request in requests {
        continuation.yield(request)
      }
      continuation.finish(throwing: failing ? StreamFailed() : nil)
    }
    return RequestStreamReader(RPCAsyncSequence(wrapping: source))
  }

  private static func payload(_ configure: (inout Idb_Payload) -> Void) -> Idb_InstallRequest {
    .with { $0.payload = .with(configure) }
  }

  private static let destination = Idb_InstallRequest.with { $0.destination = .dylib }

  private static func collect(_ stream: AsyncThrowingStream<Data, any Error>) async throws -> [Data] {
    var chunks: [Data] = []
    for try await chunk in stream {
      chunks.append(chunk)
    }
    return chunks
  }

  @Test
  func dataIsTheFirstFrameThenEveryFrameAfterIt() async throws {
    let request = try await InstallRequest.read(
      Self.frames([
        Self.destination,
        Self.payload { $0.data = Data([1]) },
        Self.payload { $0.data = Data([2]) },
        Self.payload { $0.data = Data([3]) },
      ]))
    #expect(request.header.destination == .dylib)
    guard case let .data(head, rest) = request.payload else {
      Issue.record("Expected a data payload, got \(request.payload)")
      return
    }
    #expect(head == Data([1]))
    #expect(try await Self.collect(rest) == [Data([2]), Data([3])])
  }

  @Test
  func framesWithoutDataAreSkipped() async throws {
    let request = try await InstallRequest.read(
      Self.frames([
        Self.destination,
        Self.payload { $0.data = Data([1]) },
        .with { $0.nameHint = "A" },
        Self.payload { $0.data = Data([2]) },
      ]))
    guard case let .data(_, rest) = request.payload else {
      Issue.record("Expected a data payload, got \(request.payload)")
      return
    }
    #expect(try await Self.collect(rest) == [Data([2])])
  }

  @Test
  func theRestThrowsWhenTheRequestStreamDoes() async throws {
    let request = try await InstallRequest.read(Self.frames([Self.destination, Self.payload { $0.data = Data([1]) }], failing: true))
    guard case let .data(_, rest) = request.payload else {
      Issue.record("Expected a data payload, got \(request.payload)")
      return
    }
    await #expect(throws: StreamFailed.self) {
      try await Self.collect(rest)
    }
  }

  @Test
  func aUrlIsParsed() async throws {
    let request = try await InstallRequest.read(Self.frames([Self.destination, Self.payload { $0.url = "https://example.com/a.ipa" }]))
    guard case let .url(url) = request.payload else {
      Issue.record("Expected a url payload, got \(request.payload)")
      return
    }
    #expect(url == URL(string: "https://example.com/a.ipa"))
    #expect(request.payload.kind == .url)
  }

  @Test
  func aFilePathIsPassedThrough() async throws {
    let request = try await InstallRequest.read(Self.frames([Self.destination, Self.payload { $0.filePath = "/tmp/a.app" }]))
    guard case let .filePath(path) = request.payload else {
      Issue.record("Expected a file path payload, got \(request.payload)")
      return
    }
    #expect(path == "/tmp/a.app")
    #expect(request.payload.kind == .filePath)
  }

  @Test
  func anUnparseableUrlIsRejected() async throws {
    await #expect {
      _ = try await InstallRequest.read(Self.frames([Self.destination, Self.payload { $0.url = "" }]))
    } throws: { error in
      (error as? RPCError)?.code == .invalidArgument
    }
  }
}
