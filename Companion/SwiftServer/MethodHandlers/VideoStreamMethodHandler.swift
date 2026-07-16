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

private enum VideoStreamMethodHandlerError: Error {
  case failedToCreateSyncWriter(filePath: String)
}

extension VideoStreamMethodHandlerError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .failedToCreateSyncWriter(let filePath):
      return "Failed to create sync writer for \(filePath)"
    }
  }
}

struct VideoStreamMethodHandler {

  let target: FBiOSTarget
  let targetLogger: FBControlCoreLogger
  let commandExecutor: FBIDBCommandExecutor

  func handle(requestStream: GRPCAsyncRequestStream<Idb_VideoStreamRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_VideoStreamResponse>, context: GRPCAsyncServerCallContext) async throws {
    @Atomic var finished = false

    guard case let .start(start) = try await requestStream.requiredNext.control
    else { throw GRPCStatus(code: .failedPrecondition, message: "Expected start control") }

    let videoStream = try await startVideoStream(
      request: start,
      responseStream: responseStream,
      finished: _finished)

    let observeClientCancelStreaming = Task<Void, Error> {
      for try await request in requestStream {
        switch request.control {
        case .start:
          throw GRPCStatus(code: .failedPrecondition, message: "Video streaming already started")
        case .stop:
          return
        case .none:
          throw GRPCStatus(code: .invalidArgument, message: "Client should not close request stream explicitly, send `stop` frame first")
        }
      }
    }

    let observeVideoStreamStop = Task<Void, Error> {
      try await videoStream.awaitCompletion()
    }

    try await Task.select(observeClientCancelStreaming, observeVideoStreamStop).value

    try await videoStream.stopStreaming()
    targetLogger.log("The video stream is terminated")
  }

  private func startVideoStream(request start: Idb_VideoStreamRequest.Start, responseStream: GRPCAsyncResponseStreamWriter<Idb_VideoStreamResponse>, finished: Atomic<Bool>) async throws -> FBVideoStream {
    let consumer: FBDataConsumer

    if start.filePath.isEmpty {
      let responseWriter = FIFOStreamWriter(stream: responseStream)

      consumer = FBBlockDataConsumer.asynchronousDataConsumer { data in
        guard !finished.wrappedValue else { return }
        let response = Idb_VideoStreamResponse.with {
          $0.payload.data = data
        }
        do {
          try responseWriter.send(response)
        } catch {
          finished.set(true)
        }
      }
    } else {
      var writeError: NSError?
      guard let writer = FBFileWriter.syncWriter(forFilePath: start.filePath, error: &writeError) else {
        throw writeError ?? VideoStreamMethodHandlerError.failedToCreateSyncWriter(filePath: start.filePath)
      }
      consumer = writer
    }

    let framesPerSecond = start.fps > 0 ? Int(start.fps) : nil
    let format = streamFormat(from: start.format)

    let rateControl: FBVideoStreamRateControl?
    if start.avgBitrate > 0 {
      rateControl = .bitrate(Int(start.avgBitrate))
    } else if start.compressionQuality > 0 {
      rateControl = .quality(Double(start.compressionQuality))
    } else {
      rateControl = nil
    }

    let config = FBVideoStreamConfiguration(
      format: format,
      framesPerSecond: framesPerSecond,
      rateControl: rateControl,
      scaleFactor: Double(start.scaleFactor),
      keyFrameRate: Double(start.keyFrameRate))

    guard let asyncTarget = target as? any VideoStreamCommands else {
      throw GRPCStatus(code: .failedPrecondition, message: "\(target) does not support VideoStreamCommands")
    }
    return try await asyncTarget.createStream(configuration: config, to: consumer)
  }

  private func streamFormat(from requestFormat: Idb_VideoStreamRequest.Format) -> FBVideoStreamFormat {
    switch requestFormat {
    case .h264:
      return .compressedVideo(withCodec: .h264, transport: .annexB)
    case .rbga:
      return .bgra
    case .mjpeg:
      return .mjpeg
    case .minicap:
      return .minicap
    case .i420, .UNRECOGNIZED:
      return .compressedVideo(withCodec: .h264, transport: .annexB)
    }
  }
}
