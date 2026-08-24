/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBControlCore
import GRPC
import IDBGRPCSwift

struct RecordMethodHandler {

  let target: FBiOSTarget
  let targetLogger: FBControlCoreLogger

  func handle(requestStream: GRPCAsyncRequestStream<Idb_RecordRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_RecordResponse>, context: GRPCAsyncServerCallContext) async throws {

    // grpc-swift's request stream traps if a second AsyncIterator is ever
    // created; this handler reads two frames (start, then stop), so both
    // reads must go through one owned iterator. `requestStream.requiredNext`
    // makes a fresh iterator per call and crashes the companion on the stop
    // frame, so route every read through a single SingleIteratorRequestStream.
    let stream = SingleIteratorRequestStream(requestStream)

    let request = try await stream.requiredNext
    guard case let .start(start) = request.control
    else { throw GRPCStatus(code: .failedPrecondition, message: "Expect start as initial request frame") }

    let filePath =
      start.filePath.isEmpty
      ? URL(fileURLWithPath: target.auxillaryDirectory).appendingPathComponent("idb_encode").appendingPathExtension("mp4").path
      : start.filePath

    guard let asyncTarget = target as? any VideoRecordingCommands else {
      throw GRPCStatus(code: .failedPrecondition, message: "\(target) does not support VideoRecordingCommands")
    }
    let recording = try await asyncTarget.startRecording(toFile: filePath)

    _ = try await stream.requiredNext
    let outputURL = try await recording.stop()

    if start.filePath.isEmpty {
      let gzipTask = try await FBArchiveOperations.createGzipAsync(
        forPath: outputURL.path,
        logger: targetLogger)

      try await FileDrainWriter.performDrain(task: gzipTask) { data in
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
