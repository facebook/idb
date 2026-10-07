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

struct LogMethodHandler: @unchecked Sendable {

  let target: any Target
  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_LogRequest, responseStream: RPCWriter<Idb_LogResponse>, context: ServerContext) async throws {
    let streamWriter = FIFOStreamWriter(stream: responseStream)
    try await Self.tail(cancellation: context.cancellation, send: { try streamWriter.send($0) }) { consumer in
      if request.source == .companion {
        return try await commandExecutor.tail_companion_logs(consumer)
      }
      return try await target.log.tail(arguments: request.arguments, consumer: consumer)
    }
  }

  /// Forwards the log `start` begins until the log ends, a write fails, or `cancellation` reports the RPC
  /// cancelled, as it does when the client goes away. Only a write would otherwise notice the client is gone.
  static func tail(
    cancellation: ServerContext.RPCCancellationHandle,
    send: @escaping @Sendable (Idb_LogResponse) throws -> Void,
    start: @escaping @Sendable (any DataConsumer) async throws -> any LogOperation
  ) async throws {
    try await withRPCCancellation(cancellation) {
      try await forward(send: send, start: start)
    }
  }

  private static func forward(
    send: @escaping @Sendable (Idb_LogResponse) throws -> Void,
    start: (any DataConsumer) async throws -> any LogOperation
  ) async throws {
    let writingDone = AsyncPromise<Void>()

    let consumer = SynchronousDataConsumer { data in
      if writingDone.isResolved {
        return
      }
      let response = Idb_LogResponse.with {
        $0.output = data
      }
      do {
        try send(response)
      } catch {
        writingDone.fail(error)
      }
    }

    let operation = try await start(consumer)

    let observeWritingDone = Task<Void, Error> {
      try await writingDone.value
    }
    // `operation` is a thread-safe handle but not Sendable; rebind as
    // nonisolated(unsafe) so the observer Task can capture it.
    nonisolated(unsafe) let operationToObserve = operation
    let observeOperationCompletion = Task<Void, Error> {
      try await operationToObserve.waitUntilCompleted()
    }
    try await Task.select(observeWritingDone, observeOperationCompletion).value
    writingDone.resolve(())

    observeOperationCompletion.cancel()
  }
}
