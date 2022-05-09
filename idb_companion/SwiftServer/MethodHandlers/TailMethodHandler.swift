/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import IDBGRPCSwift
import GRPC
import FBSimulatorControl

struct TailMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(requestStream: GRPCAsyncRequestStream<Idb_TailRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_TailResponse>, context: GRPCAsyncServerCallContext) async throws {
    @Atomic var finished = false
    let finishedBox = _finished // have to use it to please swift concurrency checker

    guard case let .start(start) = try await requestStream.requiredNext.control
    else { throw GRPCStatus(code: .failedPrecondition, message: "Expected start control") }

    let consumer = FBBlockDataConsumer.asynchronousDataConsumer { data in
      guard !finished else { return }
      let response = Idb_TailResponse.with {
        $0.data = data
      }
      Task {
        do {
          try await responseStream.send(response)
        } catch {
          finishedBox.sync { finished in
            finished = true
          }
        }
      }
    }

    let fileContainer = FileContainerValueTransformer.rawFileContainer(from: start.container)
    let tail = try await BridgeFuture.value(commandExecutor.tail(start.path, to_consumer: consumer, in_container: fileContainer))

    guard case .stop = try await requestStream.requiredNext.control
    else { throw GRPCStatus(code: .failedPrecondition, message: "Expected end control") }

    try await BridgeFuture.await(tail.cancel())
    finished = true
  }

}
