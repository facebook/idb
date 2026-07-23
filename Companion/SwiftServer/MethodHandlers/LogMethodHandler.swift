/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import CompanionUtilities
import FBControlCore
import FBSimulatorControl
import GRPC
import IDBGRPCSwift

struct LogMethodHandler: @unchecked Sendable {

  let target: FBiOSTarget
  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_LogRequest, responseStream: GRPCAsyncResponseStreamWriter<Idb_LogResponse>, context: GRPCAsyncServerCallContext) async throws {
    let writingDone = AsyncPromise<Void>()
    let streamWriter = FIFOStreamWriter(stream: responseStream)

    let consumer = FBBlockDataConsumer.synchronousDataConsumer { data in
      if writingDone.isResolved {
        return
      }
      let response = Idb_LogResponse.with {
        $0.output = data
      }
      do {
        try streamWriter.send(response)
      } catch {
        writingDone.fail(error)
      }
    }

    let operation: any LogOperation
    if request.source == .companion {
      operation = try await commandExecutor.tail_companion_logs(consumer)
    } else {
      guard let asyncTarget = target as? any LogCommands else {
        throw GRPCStatus(code: .failedPrecondition, message: "\(target) does not support LogCommands")
      }
      operation = try await asyncTarget.tailLog(arguments: request.arguments, consumer: consumer)
    }

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
