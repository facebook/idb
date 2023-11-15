/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import GRPC
import IDBGRPCSwift

struct RecordMethodHandler {

  let target: FBiOSTarget
  let targetLogger: FBControlCoreLogger

  func handle(requestStream: GRPCAsyncRequestStream<Idb_RecordRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_RecordResponse>, context: GRPCAsyncServerCallContext) async throws {

    let request = try await requestStream.requiredNext
    guard case let .start(start) = request.control
    else { throw GRPCStatus(code: .failedPrecondition, message: "Expect start as initial request frame") }

    let filePath =
      start.filePath.isEmpty
      ? URL(fileURLWithPath: target.auxillaryDirectory).appendingPathComponent("idb_encode").appendingPathExtension("mp4").path
      : start.filePath

    _ = try await BridgeFuture.value(target.startRecording(toFile: filePath))

    _ = try await requestStream.requiredNext
    try await BridgeFuture.await(target.stopRecording())

    if start.filePath.isEmpty {
      let gzipTask = FBArchiveOperations.createGzip(forPath: filePath,
                                                    queue: BridgeQueues.miscEventReaderQueue,
                                                    logger: targetLogger)

      try await FileDrainWriter.performDrain(taskFuture: gzipTask) { data in
        let response = Idb_RecordResponse.with { $0.payload.data = data }
        try await responseStream.send(response)
      }
    } else {
      let response = Idb_RecordResponse.with {
        $0.output = .payload(.with { $0.source = .filePath(start.filePath) })
      }
      try await responseStream.send(response)
    }
  }
}
