/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import CoreVideo
import FBControlCore
import Foundation
import IOSurface
import VideoToolbox

// MARK: - Frame Pusher Protocol

/// Frame pusher abstraction. Concrete pushers convert + write frames to the consumer.
protocol SimulatorVideoStreamFramePusher: AnyObject {
  func setup(with pixelBuffer: CVPixelBuffer, edgeInsets: VideoStreamEdgeInsets) throws
  func tearDown() throws
  func writeEncodedFrame(
    _ pixelBuffer: CVPixelBuffer,
    frameNumber: UInt,
    timeAtFirstFrame: CFTimeInterval,
    frameDuration: CFTimeInterval,
    forceKeyFrame: Bool
  ) throws
  /// The source surface changed while the frame was being read; counted in the pusher's stats.
  func recordTornFrame()
  func currentStats() -> VideoEncoderStats?
}

extension SimulatorVideoStreamFramePusher {
  func recordTornFrame() {}
  func currentStats() -> VideoEncoderStats? { nil }
}

// MARK: - VideoToolbox Output Mode

/// Selects what the VideoToolbox pusher's per-frame encode handler does with each encoded sample:
/// all H264/HEVC → `.compressed`, MJPEG → `.mjpeg`, Minicap → `.minicap`.
enum VideoToolboxOutputMode {
  /// H264/HEVC: hand the sample to `handleCompressedSampleBuffer` for framing + stats.
  case compressed
  /// MJPEG: write the sample's block buffer straight to the MJPEG stream.
  case mjpeg
  /// Minicap: emit the Minicap header on the first frame, then write each JPEG frame.
  case minicap
}

// MARK: - Bitmap Frame Pusher

/// Writes raw BGRA pixel bytes (optionally scaled) straight through to the consumer, unframed.
final class SimulatorVideoStreamFramePusher_Bitmap: SimulatorVideoStreamFramePusher {
  let consumer: any DataConsumer
  /// The scale factor between 0-1. nil for no scaling.
  let scaleFactor: Double?
  /// Present only when scaling; a frame that fails to scale is written at source size.
  private(set) var scaler: PixelBufferConverter?

  init(consumer: any DataConsumer, scaleFactor: Double?) {
    self.consumer = consumer
    self.scaleFactor = scaleFactor
  }

  func setup(with pixelBuffer: CVPixelBuffer, edgeInsets: VideoStreamEdgeInsets) throws {
    guard let scaleFactor, scaleFactor > 0, scaleFactor < 1 else {
      return
    }
    scaler = try PixelBufferConverter(
      outputWidth: Int(floor(scaleFactor * Double(CVPixelBufferGetWidth(pixelBuffer)))),
      outputHeight: Int(floor(scaleFactor * Double(CVPixelBufferGetHeight(pixelBuffer)))),
      pixelFormat: CVPixelBufferGetPixelFormatType(pixelBuffer))
  }

  func tearDown() throws {
    scaler?.invalidate()
    scaler = nil
  }

  func writeEncodedFrame(
    _ pixelBuffer: CVPixelBuffer,
    frameNumber: UInt,
    timeAtFirstFrame: CFTimeInterval,
    frameDuration: CFTimeInterval,
    forceKeyFrame: Bool
  ) throws {
    var bufferToWrite = pixelBuffer
    if let scaler, case let .converted(scaled) = scaler.convert(pixelBuffer) {
      bufferToWrite = scaled
    }

    CVPixelBufferLockBaseAddress(bufferToWrite, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(bufferToWrite, .readOnly) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(bufferToWrite) else { return }
    let size = CVPixelBufferGetDataSize(bufferToWrite)

    if consumer is DataConsumerSync {
      let data = Data(bytesNoCopy: baseAddress, count: size, deallocator: .none)
      consumer.consumeData(data)
    } else {
      let data = Data(bytes: baseAddress, count: size)
      consumer.consumeData(data)
    }
  }
}

// MARK: - VideoToolbox Frame Pusher

/// Encodes BGRA frames via a VTCompressionSession (BGRA→NV12 via `PixelBufferConverter`), then
/// writes the encoded sample to the consumer through the chosen frame writer (or, for MJPEG/Minicap,
/// directly in the encode handler). Outcomes are accounted for by `EncoderStatsRecorder`.
///
/// @unchecked Sendable: `VTCompressionSessionEncodeFrame`'s `@Sendable` output handler can run on a
/// VideoToolbox thread after the encode call returns, so it captures `self`. Everything it touches
/// is immutable or is the stats recorder, which is safe for that thread by its own contract.
/// `tearDown` flushes every pending handler before it invalidates the session.
final class SimulatorVideoStreamFramePusher_VideoToolbox: SimulatorVideoStreamFramePusher, @unchecked Sendable {
  let settings: VideoToolboxEncoderSettings
  /// The scale factor between 0-1. nil for no scaling.
  let scaleFactor: Double?
  let videoCodec: CMVideoCodecType
  let outputMode: VideoToolboxOutputMode
  /// The encoded-sample sink for `.compressed` output; nil for MJPEG/Minicap, which write the JPEG
  /// block buffer directly to `consumer` in the encode handler.
  let encodedSampleConsumer: EncodedSampleConsumer?
  let timedMetadataWriter: (any VideoStreamTimedMetadataWriter)?
  let consumer: any DataConsumer
  let logger: any ControlCoreLogger
  private let mjpegFrameWriter = MJPEGFrameWriter()
  private let minicapFrameWriter = MinicapFrameWriter()

  var compressionSession: VTCompressionSession?
  /// BGRA→NV12 at the encoded output size; nil until `setup`.
  private var converter: PixelBufferConverter?
  let statsRecorder: EncoderStatsRecorder

  init(
    settings: VideoToolboxEncoderSettings,
    scaleFactor: Double?,
    videoCodec: CMVideoCodecType,
    consumer: any DataConsumer,
    outputMode: VideoToolboxOutputMode,
    encodedSampleConsumer: EncodedSampleConsumer?,
    timedMetadataWriter: (any VideoStreamTimedMetadataWriter)?,
    logger: any ControlCoreLogger
  ) {
    self.settings = settings
    self.scaleFactor = scaleFactor
    self.outputMode = outputMode
    self.encodedSampleConsumer = encodedSampleConsumer
    self.timedMetadataWriter = timedMetadataWriter
    self.consumer = consumer
    self.logger = logger
    self.videoCodec = videoCodec
    self.statsRecorder = EncoderStatsRecorder(logger: logger)
  }

  /// The `.compressed` output path: hands the sample to the encoded-sample consumer and records the
  /// outcome.
  func handleCompressedSampleBuffer(_ sampleBuffer: CMSampleBuffer?, encodeStatus: OSStatus, infoFlags: VTEncodeInfoFlags) {
    statsRecorder.record(outcome(of: sampleBuffer, encodeStatus: encodeStatus, infoFlags: infoFlags))
  }

  private func outcome(of sampleBuffer: CMSampleBuffer?, encodeStatus: OSStatus, infoFlags: VTEncodeInfoFlags) -> EncoderStatsRecorder.Outcome {
    if encodeStatus != noErr {
      return .encodeError(encodeStatus)
    }
    if infoFlags.contains(.frameDropped) {
      return .dropped
    }
    guard let sampleBuffer, let encodedSampleConsumer, encodedSampleConsumer.consume(sampleBuffer, logger: logger) else {
      return .writeFailed
    }
    let encodedBytes = CMSampleBufferGetDataBuffer(sampleBuffer).map(CMBlockBufferGetDataLength) ?? 0
    return .written(encodedBytes: encodedBytes)
  }

  /// MJPEG output: writes the sample's JPEG block buffer straight to the stream, ignoring encode status/flags.
  private func handleMJPEGSampleBuffer(_ sampleBuffer: CMSampleBuffer?) {
    guard let sampleBuffer, let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
    do {
      try mjpegFrameWriter.write(blockBuffer, to: consumer, logger: logger)
    } catch {
      logger.log("Failed to write MJPEG frame: \(error)")
    }
  }

  /// Minicap output: on frame 0 emits the header from the sample's format dimensions, then writes each
  /// JPEG block buffer. Ignores encode status/flags.
  private func handleMinicapSampleBuffer(_ sampleBuffer: CMSampleBuffer?, frameNumber: UInt) {
    guard let sampleBuffer else { return }
    if frameNumber == 0 {
      if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        minicapFrameWriter.writeHeader(width: UInt32(dimensions.width), height: UInt32(dimensions.height), to: consumer, logger: logger)
      }
    }
    guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
    do {
      try minicapFrameWriter.write(blockBuffer, to: consumer, logger: logger)
    } catch {
      logger.log("Failed to write Minicap frame: \(error)")
    }
  }

  func setup(with pixelBuffer: CVPixelBuffer, edgeInsets: VideoStreamEdgeInsets) throws {
    let encoderSpecification = settings.encoderSpecification

    let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
    let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
    // The composited frame includes the edge insets, so the NV12 pool and compression session must
    // accommodate the full output size — the same `VideoOutputDimensions` the composited pool uses.
    let dimensions = VideoOutputDimensions.calculate(
      sourceWidth: sourceWidth, sourceHeight: sourceHeight,
      scaleFactor: scaleFactor, edgeInsets: edgeInsets)
    let destinationWidth = dimensions.width
    let destinationHeight = dimensions.height
    if let scaleFactor, scaleFactor > 0, scaleFactor < 1 {
      logger.info().log("Applying \(scaleFactor) scale from w=\(sourceWidth)/h=\(sourceHeight) to output w=\(destinationWidth)/h=\(destinationHeight)")
    }

    let converter = try PixelBufferConverter(
      outputWidth: destinationWidth, outputHeight: destinationHeight, pixelFormat: PixelBufferConverter.encoderPixelFormat)
    self.converter = converter
    logger.info().log("Created BGRA→NV12 conversion pipeline at w=\(destinationWidth)/h=\(destinationHeight) (GPU via VTPixelTransferSession)")

    // No create-time output callback: each frame is encoded with the block-based
    // `VTCompressionSessionEncodeFrame(...outputHandler:)` overload (see `writeEncodedFrame`),
    // so the session needs neither an `outputCallback` nor a `refcon`.
    var compressionSession: VTCompressionSession?
    let status = VTCompressionSessionCreate(
      allocator: nil,
      width: Int32(destinationWidth),
      height: Int32(destinationHeight),
      codecType: videoCodec,
      encoderSpecification: encoderSpecification as CFDictionary,
      imageBufferAttributes: converter.outputBufferAttributes as CFDictionary,
      compressedDataAllocator: nil,
      outputCallback: nil,
      refcon: nil,
      compressionSessionOut: &compressionSession
    )
    if status != noErr {
      throw SimulatorVideoStreamError.failedToStartCompressionSession(status: status)
    }
    guard let compressionSession else {
      throw SimulatorVideoStreamError.compressionSessionNil
    }

    let sessionProperties = settings.sessionProperties(outputWidth: destinationWidth, outputHeight: destinationHeight)
    if case .compressedVideo = settings.format {
      logger.info().log(
        "Rate control \(settings.rateControl) resolved to \(sessionProperties[kVTCompressionPropertyKey_AverageBitRate as String] ?? 0) bps average for w=\(destinationWidth)/h=\(destinationHeight)")
    }

    let propertiesStatus = VTSessionSetProperties(compressionSession, propertyDictionary: sessionProperties as CFDictionary)
    if propertiesStatus != noErr {
      throw SimulatorVideoStreamError.failedToSetCompressionSessionProperties(status: propertiesStatus)
    }
    let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(compressionSession)
    if prepareStatus != noErr {
      throw SimulatorVideoStreamError.failedToPrepareCompressionSession(status: prepareStatus)
    }
    self.compressionSession = compressionSession
  }

  func tearDown() throws {
    if let compressionSession {
      VTCompressionSessionCompleteFrames(compressionSession, untilPresentationTimeStamp: .invalid)
      VTCompressionSessionInvalidate(compressionSession)
      self.compressionSession = nil
    }
    converter?.invalidate()
    converter = nil
  }

  func writeEncodedFrame(
    _ pixelBuffer: CVPixelBuffer,
    frameNumber: UInt,
    timeAtFirstFrame: CFTimeInterval,
    frameDuration: CFTimeInterval,
    forceKeyFrame: Bool
  ) throws {
    guard let compressionSession else {
      throw SimulatorVideoStreamError.missingCompressionSession
    }

    var bufferToWrite = pixelBuffer

    let encodeStart = CFAbsoluteTimeGetCurrent()

    // BGRA→NV12 (and scale, since the pool is destination-sized) in one pass; on failure the encoder
    // takes the BGRA frame and converts internally.
    if let converter {
      switch converter.convert(pixelBuffer) {
      case let .converted(nv12Buffer):
        bufferToWrite = nv12Buffer
      case let .transferFailed(status):
        logger.log("VTPixelTransferSession BGRA→NV12 failed: \(status) — falling back to BGRA input")
      case let .poolExhausted(status):
        logger.log("Failed to get a pixel buffer from the NV12 pool: \(status)")
      }
    }

    let time = CMTimeMakeWithSeconds(ProcessInfo.processInfo.systemUptime - timeAtFirstFrame, preferredTimescale: Int32(NSEC_PER_SEC))
    let duration = frameDuration > 0 ? CMTimeMakeWithSeconds(frameDuration, preferredTimescale: Int32(NSEC_PER_SEC)) : CMTime.invalid
    var frameProperties: [String: Any]?
    if frameNumber == 0 || forceKeyFrame {
      frameProperties = [kVTEncodeFrameOptionKey_ForceKeyFrame as String: true]
    }

    // `[weak self]`: the session does not retain the pusher, so a strong capture would be a cycle
    // (pusher → session → handler → pusher). The handler may run on a VideoToolbox thread after this call
    // returns; mutable state is handler-confined or guarded by `statsLock` (see the class doc).
    let outputMode = self.outputMode
    let handler: VTCompressionOutputHandler = { [weak self] encodeStatus, infoFlags, sampleBuffer in
      guard let self else { return }
      switch outputMode {
      case .compressed:
        self.handleCompressedSampleBuffer(sampleBuffer, encodeStatus: encodeStatus, infoFlags: infoFlags)
      case .mjpeg:
        self.handleMJPEGSampleBuffer(sampleBuffer)
      case .minicap:
        self.handleMinicapSampleBuffer(sampleBuffer, frameNumber: frameNumber)
      }
    }

    let status = VTCompressionSessionEncodeFrame(
      compressionSession,
      imageBuffer: bufferToWrite,
      presentationTimeStamp: time,
      duration: duration,
      frameProperties: frameProperties as CFDictionary?,
      infoFlagsOut: nil,
      outputHandler: handler
    )

    statsRecorder.recordEncodeSubmission(seconds: CFAbsoluteTimeGetCurrent() - encodeStart)

    if status != 0 {
      throw SimulatorVideoStreamError.failedToCompress(status: status)
    }
  }

  func recordTornFrame() {
    statsRecorder.recordTornFrame()
  }

  func currentStats() -> VideoEncoderStats? {
    statsRecorder.snapshot
  }
}
