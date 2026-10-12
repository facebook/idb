/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
@preconcurrency import FBControlCore
import FBSimulatorControl
import Foundation
import GRPCCore
import IDBGRPCSwift
import ShimulatorAudioInjectionCore
import Testing

@Suite
final class InjectAudioMethodHandlerTests {
  private let temporaryDirectory = TemporaryDirectory(logger: ControlCoreGlobalConfiguration.defaultLogger)

  deinit { temporaryDirectory.cleanOnExit() }

  @Test
  func mapsExpectedAudioFailuresToClientStatuses() {
    #expect(InjectAudioMethodHandler.rpcError(for: .injectionUnreadable(path: "/tmp/not.wav")).code == .invalidArgument)
    #expect(InjectAudioMethodHandler.rpcError(for: .injectionAlreadyRunning(udid: "simulator")).code == .failedPrecondition)
    #expect(InjectAudioMethodHandler.rpcError(for: .injectionShimMissing(item: "shim")).code == .internalError)
    #expect(
      InjectAudioMethodHandler.rpcError(for: IDBCommandError.notASimulator(targetDescription: "physical device"))?.code
        == .failedPrecondition)
    #expect(InjectAudioMethodHandler.rpcError(for: IDBCommandError.invalidURL(urlString: "not a URL")) == nil)
  }

  @Test
  func materializesRawAudioDataAsOneTemporaryFile() async throws {
    let observed = try await withAudioFile([.data(Data([0, 1])), .data(Data([2, 3]))]) { url in
      #expect(url.lastPathComponent == "input.wav")
      return try Data(contentsOf: url)
    }
    #expect(observed == Data([0, 1, 2, 3]))
  }

  @Test
  func acceptsExactlyOneLocalRegularFile() async throws {
    let file = try makeFile()
    defer { try? FileManager.default.removeItem(at: file) }

    #expect(try await withAudioFile([.filePath(file.path)]) { $0 } == file)
  }

  @Test
  func rejectsAdditionalFramesAfterALocalPath() async throws {
    let file = try makeFile()
    defer { try? FileManager.default.removeItem(at: file) }

    let error = await #expect(throws: RPCError.self) {
      try await self.withAudioFile([.filePath(file.path), .filePath(file.path)]) { _ in }
    }
    #expect(error?.message == "Audio injection requires exactly one local file path")
  }

  @Test
  func rejectsNonDataFramesAndMissingFiles() async {
    for sources: [Idb_Payload.OneOf_Source] in [
      [.data(Data([0, 1])), .filePath("/tmp/input.wav")], [.filePath("/tmp/idb-inject-audio-missing.wav")],
    ] {
      await #expect(throws: RPCError.self) { try await self.withAudioFile(sources) { _ in } }
    }
  }

  @Test
  func rejectsRemoteAudioOverThePayloadLimit() async {
    let maximumBytes = ShimulatorAudioInjection.maximumPayloadBytes
    for frames in [[Data(count: maximumBytes + 1)], [Data(count: maximumBytes), Data([0])]] {
      await #expect(throws: RPCError.self) {
        try await self.withAudioFile(frames.map { .data($0) }) { _ in Issue.record("Audio over the limit was accepted") }
      }
    }
  }

  @Test
  func cancellationAfterRequestEOFJoinsInjectionAndRemovesTemporaryFile() async throws {
    let cancellation = ServerContext.RPCCancellationHandle()
    let (started, startContinuation) = AsyncStream<URL>.makeStream()
    let (finished, finishContinuation) = AsyncStream<Bool>.makeStream()
    async let result: Void = InjectAudioMethodHandler.withAudioInjection(
      from: requestStream([.data(Data([0, 1, 2, 3]))]),
      temporaryDirectory: temporaryDirectory, cancellation: cancellation
    ) { url in
      defer {
        finishContinuation.yield(true)
        finishContinuation.finish()
      }
      startContinuation.yield(url)
      startContinuation.finish()
      try await Task.sleep(nanoseconds: 30_000_000_000)
    }
    var starts = started.makeAsyncIterator()
    let url = try #require(await starts.next())
    #expect(FileManager.default.fileExists(atPath: url.path))
    cancellation.cancel()
    do {
      try await result
      Issue.record("RPC cancellation did not cancel injection")
    } catch is CancellationError {
    }
    var finishes = finished.makeAsyncIterator()
    #expect(await finishes.next() == true)
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  private func withAudioFile<T>(
    _ sources: [Idb_Payload.OneOf_Source], _ body: (URL) async throws -> T
  ) async throws -> T {
    try await InjectAudioMethodHandler.withAudioFile(
      from: requestStream(sources), temporaryDirectory: temporaryDirectory, body)
  }

  private func makeFile() throws -> URL {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("idb-inject-audio-\(UUID().uuidString).wav")
    try Data([0, 1, 2, 3]).write(to: file)
    return file
  }

  private func requestStream(
    _ sources: [Idb_Payload.OneOf_Source]
  ) -> RequestStreamReader<Idb_InjectAudioRequest> {
    let stream = AsyncThrowingStream<Idb_InjectAudioRequest, any Error> { continuation in
      for source in sources {
        continuation.yield(
          Idb_InjectAudioRequest.with {
            $0.payload = Idb_Payload.with { $0.source = source }
          })
      }
      continuation.finish()
    }
    return RequestStreamReader(RPCAsyncSequence(wrapping: stream))
  }
}
