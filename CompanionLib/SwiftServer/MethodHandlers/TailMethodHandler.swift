/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionUtilities
import FBControlCore
import FBSimulatorControl
import GRPCCore
import IDBGRPCSwift

protocol TailOperation {
  func cancel() async throws
}

extension FileContainerTailOperation: TailOperation {}

struct TailMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(requestStream: RequestStreamReader<Idb_TailRequest>, responseStream: RPCWriter<Idb_TailResponse>, context: ServerContext) async throws {
    guard case let .start(start) = try await requestStream.requiredNext().control
    else { throw RPCError(code: .failedPrecondition, message: "Expected start control") }

    let responseWriter = FIFOStreamWriter(stream: responseStream)
    let fileContainer = FileContainerValueTransformer.rawFileContainer(from: start.container)
    try await Self.tail(
      send: { try responseWriter.send($0) },
      awaitStop: {
        guard case .stop = try await requestStream.requiredNext().control
        else { throw RPCError(code: .failedPrecondition, message: "Expected end control") }
      },
      start: { consumer in
        try await commandExecutor.tail(start.path, to_consumer: consumer, in_container: fileContainer)
      })
  }

  /// Forwards the tail `start` begins until `awaitStop` returns or throws, then cancels it.
  static func tail(
    send: @escaping @Sendable (Idb_TailResponse) throws -> Void,
    awaitStop: () async throws -> Void,
    start: (any DataConsumer) async throws -> any TailOperation
  ) async throws {
    @Atomic var finished = false

    let consumer = FBBlockDataConsumer.asynchronousDataConsumer { data in
      guard !finished else { return }
      let response = Idb_TailResponse.with {
        $0.data = data
      }
      do {
        try send(response)
      } catch {
        _finished.set(true)
      }
    }

    let tail = try await start(consumer)
    do {
      try await awaitStop()
    } catch {
      // A client that goes away without a stop ends the stream here, and nothing else would stop the tail.
      _finished.set(true)
      try? await tail.cancel()
      throw error
    }
    try await tail.cancel()
    _finished.set(true)
  }
}
