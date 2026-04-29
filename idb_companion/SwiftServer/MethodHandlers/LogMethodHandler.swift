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

    let operationFuture =
      request.source == .companion
      ? commandExecutor.tail_companion_logs(consumer)
      : target.tailLog(request.arguments, consumer: consumer)

    let operation = try await bridgeFBFuture(operationFuture)

    let completed = FBFuture(race: [convertFBMutableFuture(writingDone), operation.completed])

    try await bridgeFBFutureVoid(completed)
    writingDone.resolve(withResult: NSNull())

    try await bridgeFBFutureVoid(operation.completed.cancel())
  }
}
