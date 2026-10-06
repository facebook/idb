/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import GRPCCore
import IDBGRPCSwift

struct RecordMethodHandler {

  let target: any Target
  let targetLogger: ControlCoreLogger

  /// Stops `recording`, returning the file to deliver and the failure to report once it has been.
  ///
  /// Finalizing can fail with a usable recording already on disk: every frame has been written by
  /// this point and it is the closing write that fails. Reporting that before the file is sent
  /// costs the caller a recording that exists, so the error is handed back rather than thrown and
  /// the caller delivers first. The fallback path is the file the recording was started against,
  /// which is where those frames are.
  static func finalizeForDelivery(
    _ recording: any VideoRecording,
    fallbackPath: String,
    logger: any ControlCoreLogger,
  ) async -> (outputURL: URL, finalizeError: (any Error)?) {
    do {
      return (try await recording.stop(), nil)
    } catch {
      logger.log("Recording did not finalize cleanly, sending what was written: \(error)")
      return (URL(fileURLWithPath: fallbackPath), error)
    }
  }

  func handle(requestStream: RequestStreamReader<Idb_RecordRequest>, responseStream: RPCWriter<Idb_RecordResponse>, context: ServerContext) async throws {

    let request = try await requestStream.requiredNext()
    guard case let .start(start) = request.control
    else { throw RPCError(code: .failedPrecondition, message: "Expect start as initial request frame") }

    let filePath =
      start.filePath.isEmpty
      ? URL(fileURLWithPath: target.auxillaryDirectory).appendingPathComponent("idb_encode").appendingPathExtension("mp4").path
      : start.filePath

    let recording: any VideoRecording
    if let encodeOptions = try RecordRequestTranslation.encodeOptions(from: start) {
      try RecordRequestTranslation.requireHonoredConfiguration(target.videoRecording, describing: "\(target)")
      recording = try await target.videoRecording.start(
        toFile: filePath,
        configuration: RecordRequestTranslation.configuration(for: encodeOptions))
      do {
        // Ahead of any payload, so a client reading the stream in order learns what it is about to
        // receive before it receives any of it.
        try await responseStream.send(RecordRequestTranslation.appliedResponse(encodeOptions))
      } catch {
        // The recording is already running and this is the last thing that will reach the client, so
        // stop it rather than leaving the encoder and its file handle held for the life of the
        // companion. The original failure is what the caller needs to see.
        _ = try? await recording.stop()
        throw error
      }
    } else {
      recording = try await target.videoRecording.start(toFile: filePath)
    }

    _ = try await requestStream.requiredNext()

    let (outputURL, finalizeError) = await Self.finalizeForDelivery(
      recording,
      fallbackPath: filePath,
      logger: targetLogger)

    try await Self.deliverThenReport(
      outputURL: outputURL,
      streamingToClient: start.filePath.isEmpty,
      localFilePath: start.filePath,
      finalizeError: finalizeError,
      responseStream: responseStream,
      logger: targetLogger)
  }

  /// Sends the recording, and only then reports a finalize failure.
  ///
  /// The order is the whole point. Reporting first aborts the RPC with the file still sitting on
  /// this host, which is how a recording that existed was lost: the caller received no bytes at all.
  static func deliverThenReport(
    outputURL: URL,
    streamingToClient: Bool,
    localFilePath: String,
    finalizeError: (any Error)?,
    responseStream: RPCWriter<Idb_RecordResponse>,
    logger: any ControlCoreLogger,
  ) async throws {
    if streamingToClient {
      // A finalize that failed before the file was created leaves nothing to send, and gzip would
      // fail on the missing path with an error that hides the real one.
      if FileManager.default.fileExists(atPath: outputURL.path) {
        try await FileDrainWriter.performDrain(FBArchiveOperations.gzipSubprocess(forPath: outputURL.path), logger: logger) { data in
          let response = Idb_RecordResponse.with { $0.payload.data = data }
          try await responseStream.send(response)
        }
      }
    } else {
      let response = Idb_RecordResponse.with {
        $0.output = .payload(.with { $0.source = .filePath(localFilePath) })
      }
      try await responseStream.send(response)
    }

    if let finalizeError {
      throw finalizeError
    }
  }
}
