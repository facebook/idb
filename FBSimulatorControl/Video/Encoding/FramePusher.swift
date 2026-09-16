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

/// Stats tracked by the video encoder (VideoToolbox).
/// Zeroed if the stream uses a non-encoded format (e.g. bitmap/BGRA).
public struct VideoEncoderStats: Sendable {
  public var callbackCount: UInt
  public var writeCount: UInt
  public var dropCount: UInt
  var writeFailureCount: UInt
  public var encodeErrorCount: UInt
  public var tornFrameCount: UInt
  public var totalEncodedBytes: UInt
  var totalEncodeSubmitSeconds: CFTimeInterval

  public init() {
    self.callbackCount = 0
    self.writeCount = 0
    self.dropCount = 0
    self.writeFailureCount = 0
    self.encodeErrorCount = 0
    self.tornFrameCount = 0
    self.totalEncodedBytes = 0
    self.totalEncodeSubmitSeconds = 0
  }

  public init(
    callbackCount: UInt,
    writeCount: UInt,
    dropCount: UInt,
    writeFailureCount: UInt,
    encodeErrorCount: UInt,
    tornFrameCount: UInt,
    totalEncodedBytes: UInt,
    totalEncodeSubmitSeconds: CFTimeInterval
  ) {
    self.callbackCount = callbackCount
    self.writeCount = writeCount
    self.dropCount = dropCount
    self.writeFailureCount = writeFailureCount
    self.encodeErrorCount = encodeErrorCount
    self.tornFrameCount = tornFrameCount
    self.totalEncodedBytes = totalEncodedBytes
    self.totalEncodeSubmitSeconds = totalEncodeSubmitSeconds
  }
}

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

/// Encodes BGRA frames via a VTCompressionSession (BGRA→NV12 via VTPixelTransferSession), then
/// writes the encoded sample to the consumer through the chosen frame writer (or, for MJPEG/Minicap,
/// directly in the encode handler). Tracks warmup/starvation counters and periodic stats.
///
/// @unchecked Sendable: `VTCompressionSessionEncodeFrame`'s `@Sendable` output handler can run on a
/// VideoToolbox thread after the encode call returns, so it captures `self`. Encoder state
/// (warmup/starvation counters, `statsTimer`, `lastLoggedStats`) is only ever touched from that
/// handler, and VideoToolbox invokes a session's output handlers serially, in decode order, so they
/// never overlap each other; the owning actor's frame submissions touch none of it. `stats` is
/// additionally read by `currentStats()` from other isolation domains and written by both sides, so
/// it alone is guarded by `statsLock`. `tearDown` flushes every pending handler before it invalidates
/// the session.
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

  var consecutiveNotReadyFrameCount: UInt = 0
  var warmupComplete = false
  var starvationWarningLogged = false
  var stats = VideoEncoderStats()
  var lastLoggedStats = VideoEncoderStats()
  var statsTimer = PeriodicStatsTimer(interval: 5.0)

  // Guards `stats` only: written from the VideoToolbox handler thread and the encode submission,
  // read by `currentStats()` from arbitrary isolation domains.
  private let statsLock = NSLock()

  private func withStats<T>(_ body: (inout VideoEncoderStats) -> T) -> T {
    statsLock.lock()
    defer { statsLock.unlock() }
    return body(&stats)
  }

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
  }

  func handleCompressedSampleBuffer(_ sampleBuffer: CMSampleBuffer?, encodeStatus: OSStatus, infoFlags: VTEncodeInfoFlags) {
    if !statsTimer.hasStarted {
      _ = statsTimer.tick()
      logger.info().log("First encode callback received")
    }

    processCompressedSampleBuffer(sampleBuffer, encodeStatus: encodeStatus, infoFlags: infoFlags)

    guard case let .elapsed(intervalDuration, totalElapsed) = statsTimer.tick() else {
      return
    }

    let current = withStats { $0 }
    let last = lastLoggedStats
    let intervalCallbacks = current.callbackCount - last.callbackCount
    let intervalWritten = current.writeCount - last.writeCount
    let intervalDropped = current.dropCount - last.dropCount
    let intervalWriteFailures = current.writeFailureCount - last.writeFailureCount
    let intervalEncodeErrors = current.encodeErrorCount - last.encodeErrorCount
    let intervalTornFrames = current.tornFrameCount - last.tornFrameCount
    let intervalEncodedBytes = current.totalEncodedBytes - last.totalEncodedBytes
    let intervalEncodeSubmitSeconds = current.totalEncodeSubmitSeconds - last.totalEncodeSubmitSeconds
    lastLoggedStats = current

    let totalFps = totalElapsed > 0 ? Double(current.callbackCount) / totalElapsed : 0
    let intervalFps = intervalDuration > 0 ? Double(intervalCallbacks) / intervalDuration : 0
    let intervalBitrateKbps = intervalDuration > 0 ? Double(intervalEncodedBytes) * 8.0 / 1000.0 / intervalDuration : 0
    let totalBitrateKbps = totalElapsed > 0 ? Double(current.totalEncodedBytes) * 8.0 / 1000.0 / totalElapsed : 0
    let intervalAvgEncodeMs = intervalCallbacks > 0 ? (intervalEncodeSubmitSeconds / Double(intervalCallbacks)) * 1000.0 : 0
    let totalAvgEncodeMs = current.callbackCount > 0 ? (current.totalEncodeSubmitSeconds / Double(current.callbackCount)) * 1000.0 : 0

    logger.info().log(
      String(
        format:
          "Video stats (interval): %lu callbacks in %.1fs (%.1f fps, %.0f kbps, %.2f ms/frame encode) — %lu written, %lu dropped, %lu write failures, %lu encode errors, %lu torn",
        intervalCallbacks, intervalDuration, intervalFps, intervalBitrateKbps, intervalAvgEncodeMs,
        intervalWritten, intervalDropped, intervalWriteFailures, intervalEncodeErrors, intervalTornFrames))
    logger.info().log(
      String(
        format:
          "Video stats (total): %lu callbacks in %.1fs (%.1f fps, %.0f kbps, %.2f ms/frame encode) — %lu written, %lu dropped, %lu write failures, %lu encode errors, %lu torn",
        current.callbackCount, totalElapsed, totalFps, totalBitrateKbps, totalAvgEncodeMs,
        current.writeCount, current.dropCount, current.writeFailureCount, current.encodeErrorCount, current.tornFrameCount))
  }

  private func processCompressedSampleBuffer(_ sampleBuffer: CMSampleBuffer?, encodeStatus: OSStatus, infoFlags: VTEncodeInfoFlags) {
    withStats { $0.callbackCount += 1 }

    if encodeStatus != noErr {
      withStats { $0.encodeErrorCount += 1 }
      logger.log("VideoToolbox encode error: OSStatus \(encodeStatus)")
      return
    }

    let frameDropped = infoFlags.contains(.frameDropped)
    var writeSucceeded = false
    if !frameDropped, let sampleBuffer {
      if let encodedSampleConsumer {
        writeSucceeded = encodedSampleConsumer.consume(sampleBuffer, logger: logger)
      }
      if writeSucceeded {
        if let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
          withStats { $0.totalEncodedBytes += UInt(CMBlockBufferGetDataLength(dataBuffer)) }
        }
      }
    }

    if frameDropped || !writeSucceeded {
      if frameDropped {
        withStats { $0.dropCount += 1 }
      } else {
        withStats { $0.writeFailureCount += 1 }
      }
      consecutiveNotReadyFrameCount += 1
      let consecutiveFailures = consecutiveNotReadyFrameCount

      if !warmupComplete {
        let warmupWindowFrames: UInt = 20
        if consecutiveFailures == warmupWindowFrames {
          logger.log("Encoder has not produced a frame after \(consecutiveFailures) attempts — bitrate may be too low for this resolution")
          starvationWarningLogged = true
        }
      } else {
        let starvationThreshold: UInt = 10
        if consecutiveFailures == starvationThreshold && !starvationWarningLogged {
          logger.log("Encoder starvation: \(consecutiveFailures) consecutive frames not ready after warmup — bitrate is likely too low")
          starvationWarningLogged = true
        }
      }
      return
    }

    withStats { $0.writeCount += 1 }
    let failuresBefore = consecutiveNotReadyFrameCount
    consecutiveNotReadyFrameCount = 0
    starvationWarningLogged = false

    if !warmupComplete {
      warmupComplete = true
      if failuresBefore > 0 {
        logger.log("Encoder warmed up after \(failuresBefore) skipped frames")
      }
    }
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

    let encodeEnd = CFAbsoluteTimeGetCurrent()
    withStats { $0.totalEncodeSubmitSeconds += (encodeEnd - encodeStart) }

    if status != 0 {
      throw SimulatorVideoStreamError.failedToCompress(status: status)
    }
  }

  func recordTornFrame() {
    withStats { $0.tornFrameCount += 1 }
  }

  func currentStats() -> VideoEncoderStats? {
    withStats { $0 }
  }
}
