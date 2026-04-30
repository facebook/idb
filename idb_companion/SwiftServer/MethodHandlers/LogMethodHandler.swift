/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBControlCore
import FBSimulatorControl
import GRPC
import IDBCompanionUtilities
import IDBGRPCSwift

struct LogMethodHandler {

  let target: FBiOSTarget
  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_LogRequest, responseStream: GRPCAsyncResponseStreamWriter<Idb_LogResponse>, context: GRPCAsyncServerCallContext) async throws {
    let writingDone = FBMutableFuture<NSNull>(name: nil)
    let streamWriter = FIFOStreamWriter(stream: responseStream)

    let consumer = FBBlockDataConsumer.synchronousDataConsumer { data in
      if writingDone.hasCompleted {
        return
      }
      let response = Idb_LogResponse.with {
        $0.output = data
      }
      do {
        try streamWriter.send(response)
      } catch {
        writingDone.resolveWithError(error)
      }
    }

    let operation: FBLogOperation =
      request.source == .companion
      ? try await commandExecutor.tail_companion_logs(consumer)
      : try await target.tailLogAsync(arguments: request.arguments, consumer: consumer)

    let observeWritingDone = Task<Void, Error> {
      try await bridgeFBFutureVoid(convertFBMutableFuture(writingDone))
    }
    let observeOperationCompletion = Task<Void, Error> {
      try await operation.awaitCompletionAsync()
    }
    try await Task.select(observeWritingDone, observeOperationCompletion).value
    writingDone.resolve(withResult: NSNull())

    try await operation.cancelAsync()
  }
}
