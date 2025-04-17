/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBSimulatorControl
import GRPC
import IDBCompanionUtilities
import IDBGRPCSwift

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
      try await BridgeFuture.await(videoStream.completed)
    }

    try await Task.select(observeClientCancelStreaming, observeVideoStreamStop).value

    try await BridgeFuture.await(videoStream.stopStreaming())
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
      consumer = try FBFileWriter.syncWriter(forFilePath: start.filePath)
    }

    let framesPerSecond = start.fps > 0 ? NSNumber(value: start.fps) : nil
    let avgBitrate = start.avgBitrate > 0 ? NSNumber(value: start.avgBitrate) : nil
    let encoding = try streamEncoding(from: start.format)
    let config = FBVideoStreamConfiguration(
      encoding: encoding,
      framesPerSecond: framesPerSecond,
      compressionQuality: .init(value: start.compressionQuality),
      scaleFactor: .init(value: start.scaleFactor),
      avgBitrate: avgBitrate,
      keyFrameRate: .init(value: start.keyFrameRate))

    let videoStream = try await BridgeFuture.value(target.createStream(with: config))

    try await BridgeFuture.await(videoStream.startStreaming(consumer))

    return videoStream
  }

  private func streamEncoding(from requestFormat: Idb_VideoStreamRequest.Format) throws -> FBVideoStreamEncoding {
    switch requestFormat {
    case .h264:
      return .H264
    case .rbga:
      return .BGRA
    case .mjpeg:
      return .MJPEG
    case .minicap:
      return .minicap
    case .i420, .UNRECOGNIZED:
      throw GRPCStatus(code: .invalidArgument, message: "Unrecognized video format")
    }
  }
}
