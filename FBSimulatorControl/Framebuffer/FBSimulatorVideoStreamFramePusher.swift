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
public struct FBVideoEncoderStats: Sendable {
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
/// This is a plain Swift protocol (not `@objc`) — the pushers are only ever constructed and used
/// from Swift, and the throwing methods read more naturally than the original ObjC
/// `BOOL`/`NSError**` surface.
protocol FBSimulatorVideoStreamFramePusher: AnyObject {
  func setup(with pixelBuffer: CVPixelBuffer, edgeInsets: FBVideoStreamEdgeInsets) throws
  func tearDown() throws
  func writeEncodedFrame(
    _ pixelBuffer: CVPixelBuffer,
    frameNumber: UInt,
    timeAtFirstFrame: CFTimeInterval,
    frameDuration: CFTimeInterval,
    forceKeyFrame: Bool
  ) throws
  func currentStats() -> FBVideoEncoderStats?
}

extension FBSimulatorVideoStreamFramePusher {
  func currentStats() -> FBVideoEncoderStats? { nil }
}

// MARK: - VideoToolbox Output Mode

/// Selects what the VideoToolbox pusher's per-frame encode handler does with each encoded sample:
/// all H264/HEVC → `.compressed`, MJPEG → `.mjpeg`, Minicap → `.minicap`.
enum FBVideoToolboxOutputMode {
  /// H264/HEVC: hand the sample to `handleCompressedSampleBuffer` for framing + stats.
  case compressed
  /// MJPEG: write the sample's block buffer straight to the MJPEG stream.
  case mjpeg
  /// Minicap: emit the Minicap header on the first frame, then write each JPEG frame.
  case minicap
}

// MARK: - Pixel Buffer Pool Helpers

private func createScaledPixelBufferPool(sourceBuffer: CVPixelBuffer, scaleFactor: Double) -> CVPixelBufferPool? {
  let sourceWidth = CVPixelBufferGetWidth(sourceBuffer)
  let sourceHeight = CVPixelBufferGetHeight(sourceBuffer)

  let destinationWidth = Int(floor(scaleFactor * Double(sourceWidth)))
  let destinationHeight = Int(floor(scaleFactor * Double(sourceHeight)))

  let pixelBufferAttributes: [String: Any] = [
    kCVPixelBufferWidthKey as String: destinationWidth,
    kCVPixelBufferHeightKey as String: destinationHeight,
    kCVPixelBufferPixelFormatTypeKey as String: CVPixelBufferGetPixelFormatType(sourceBuffer),
    kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
  ]
  let pixelBufferPoolAttributes: [String: Any] = [
    kCVPixelBufferPoolMinimumBufferCountKey as String: 4,
    kCVPixelBufferPoolAllocationThresholdKey as String: 16,
  ]

  var scaledPixelBufferPool: CVPixelBufferPool?
  CVPixelBufferPoolCreate(nil, pixelBufferPoolAttributes as CFDictionary, pixelBufferAttributes as CFDictionary, &scaledPixelBufferPool)
  return scaledPixelBufferPool
}

private func createNV12PixelBufferPool(width: Int, height: Int) -> CVPixelBufferPool? {
  let pixelBufferAttributes: [String: Any] = [
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
  ]
  let pixelBufferPoolAttributes: [String: Any] = [
    kCVPixelBufferPoolMinimumBufferCountKey as String: 4,
    kCVPixelBufferPoolAllocationThresholdKey as String: 16,
  ]
  var pool: CVPixelBufferPool?
  CVPixelBufferPoolCreate(nil, pixelBufferPoolAttributes as CFDictionary, pixelBufferAttributes as CFDictionary, &pool)
  return pool
}

/// The output dimensions shared by the encoder pipeline and the composited-frame pool: the source
/// scaled by the optional factor (only factors strictly between 0 and 1 apply), expanded by the edge
/// insets, then rounded up to even — H.264 and NV12 require even dimensions. The VideoToolbox
/// session and the composited pool must agree on these exactly (a mismatch feeds the encoder frames
/// of a different size than it was created for, distorting the output), so both sites derive them
/// from this single computation.
struct FBVideoOutputDimensions: Equatable {
  let width: Int
  let height: Int

  static func calculate(sourceWidth: Int, sourceHeight: Int, scaleFactor: Double?, edgeInsets: FBVideoStreamEdgeInsets) -> FBVideoOutputDimensions {
    var width = sourceWidth
    var height = sourceHeight
    if let scaleFactor, scaleFactor > 0, scaleFactor < 1 {
      width = Int(floor(scaleFactor * Double(sourceWidth)))
      height = Int(floor(scaleFactor * Double(sourceHeight)))
    }
    width += Int(edgeInsets.left + edgeInsets.right)
    height += Int(edgeInsets.top + edgeInsets.bottom)
    width += width % 2
    height += height % 2
    return FBVideoOutputDimensions(width: width, height: height)
  }
}

// MARK: - Bitmap Frame Pusher

/// Writes raw BGRA pixel bytes (optionally scaled) straight through to the consumer, unframed.
final class FBSimulatorVideoStreamFramePusher_Bitmap: FBSimulatorVideoStreamFramePusher {
  let consumer: any FBDataConsumer
  /// The scale factor between 0-1. nil for no scaling.
  let scaleFactor: Double?
  /// CV/VT types are ARC-managed in Swift; held strong, released automatically.
  var scaledPixelBufferPool: CVPixelBufferPool?
  var pixelTransferSession: VTPixelTransferSession?

  init(consumer: any FBDataConsumer, scaleFactor: Double?) {
    self.consumer = consumer
    self.scaleFactor = scaleFactor
  }

  func setup(with pixelBuffer: CVPixelBuffer, edgeInsets: FBVideoStreamEdgeInsets) throws {
    if let scaleFactor, scaleFactor > 0, scaleFactor < 1 {
      self.scaledPixelBufferPool = createScaledPixelBufferPool(sourceBuffer: pixelBuffer, scaleFactor: scaleFactor)
      var transferSession: VTPixelTransferSession?
      let status = VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &transferSession)
      if status != noErr {
        throw FBSimulatorVideoStreamError.failedToCreatePixelTransferSession(status: status)
      }
      self.pixelTransferSession = transferSession
    }
  }

  func tearDown() throws {
    if let pixelTransferSession {
      VTPixelTransferSessionInvalidate(pixelTransferSession)
      self.pixelTransferSession = nil
    }
    // CVPixelBufferPool is ARC-managed; dropping the reference releases it.
    self.scaledPixelBufferPool = nil
  }

  func writeEncodedFrame(
    _ pixelBuffer: CVPixelBuffer,
    frameNumber: UInt,
    timeAtFirstFrame: CFTimeInterval,
    frameDuration: CFTimeInterval,
    forceKeyFrame: Bool
  ) throws {
    var bufferToWrite = pixelBuffer
    if let bufferPool = scaledPixelBufferPool, let pixelTransferSession {
      var resizedBuffer: CVPixelBuffer?
      if CVPixelBufferPoolCreatePixelBuffer(nil, bufferPool, &resizedBuffer) == kCVReturnSuccess, let resizedBuffer {
        let status = VTPixelTransferSessionTransferImage(pixelTransferSession, from: pixelBuffer, to: resizedBuffer)
        if status == noErr {
          bufferToWrite = resizedBuffer
        }
      }
    }

    CVPixelBufferLockBaseAddress(bufferToWrite, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(bufferToWrite, .readOnly) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(bufferToWrite) else { return }
    let size = CVPixelBufferGetDataSize(bufferToWrite)

    if consumer is FBDataConsumerSync {
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
/// handler and the owning actor's frame submissions, which alternate one frame at a time (the
/// encoder is configured with `MaxFrameDelayCount: 0` and real-time low-latency rate control, so a
/// frame's handler completes before the next `writeEncodedFrame` is submitted). `stats` is
/// additionally read by `currentStats()` from other isolation domains, so it alone is guarded by
/// `statsLock`.
final class FBSimulatorVideoStreamFramePusher_VideoToolbox: FBSimulatorVideoStreamFramePusher, @unchecked Sendable {
  let configuration: FBVideoStreamConfiguration
  let compressionSessionProperties: [String: Any]
  let videoCodec: CMVideoCodecType
  let outputMode: FBVideoToolboxOutputMode
  /// The encoded-sample sink for `.compressed` output; nil for MJPEG/Minicap, which write the JPEG
  /// block buffer directly to `consumer` in the encode handler.
  let encodedSampleConsumer: FBEncodedSampleConsumer?
  let timedMetadataWriter: (any FBVideoStreamTimedMetadataWriter)?
  let consumer: any FBDataConsumer
  let logger: any FBControlCoreLogger
  private let mjpegFrameWriter = FBMJPEGFrameWriter()
  private let minicapFrameWriter = FBMinicapFrameWriter()

  /// CV/VT types are ARC-managed in Swift; held strong, released automatically.
  var compressionSession: VTCompressionSession?
  var scaledPixelBufferPool: CVPixelBufferPool?
  var nv12PixelBufferPool: CVPixelBufferPool?
  var pixelTransferSession: VTPixelTransferSession?

  // Exposed as internal (not private) so @testable tests can assert on encoder state.
  var consecutiveNotReadyFrameCount: UInt = 0
  var warmupComplete = false
  var starvationWarningLogged = false
  var stats = FBVideoEncoderStats()
  var lastLoggedStats = FBVideoEncoderStats()
  var statsTimer = FBPeriodicStatsTimer(interval: 5.0)

  // Guards `stats` only: written from the VideoToolbox handler thread and the encode submission,
  // read by `currentStats()` from arbitrary isolation domains.
  private let statsLock = NSLock()

  private func withStats<T>(_ body: (inout FBVideoEncoderStats) -> T) -> T {
    statsLock.lock()
    defer { statsLock.unlock() }
    return body(&stats)
  }

  init(
    configuration: FBVideoStreamConfiguration,
    compressionSessionProperties: [String: Any],
    videoCodec: CMVideoCodecType,
    consumer: any FBDataConsumer,
    outputMode: FBVideoToolboxOutputMode,
    encodedSampleConsumer: FBEncodedSampleConsumer?,
    timedMetadataWriter: (any FBVideoStreamTimedMetadataWriter)?,
    logger: any FBControlCoreLogger
  ) {
    self.configuration = configuration
    self.compressionSessionProperties = compressionSessionProperties
    self.outputMode = outputMode
    self.encodedSampleConsumer = encodedSampleConsumer
    self.timedMetadataWriter = timedMetadataWriter
    self.consumer = consumer
    self.logger = logger
    self.videoCodec = videoCodec
  }

  func handleCompressedSampleBuffer(_ sampleBuffer: CMSampleBuffer?, encodeStatus: OSStatus, infoFlags: VTEncodeInfoFlags) {
    if !statsTimer.hasStarted {
      // First call — start the timer.
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

    // Success
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

  /// MJPEG output: write the encoded sample's JPEG block buffer straight to the MJPEG stream.
  /// Ignores encode status/flags, matching the former `MJPEGCompressorCallback`.
  private func handleMJPEGSampleBuffer(_ sampleBuffer: CMSampleBuffer?) {
    guard let sampleBuffer, let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
    do {
      try mjpegFrameWriter.write(blockBuffer, to: consumer, logger: logger)
    } catch {
      logger.log("Failed to write MJPEG frame: \(error)")
    }
  }

  /// Minicap output: on frame 0 emit the Minicap header (from the sample's format dimensions), then
  /// write the JPEG block buffer to the Minicap stream. Ignores encode status/flags, matching the
  /// former `MinicapCompressorCallback` — the frame number is captured from `writeEncodedFrame`
  /// rather than carried through a source-frame holder.
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

  func setup(with pixelBuffer: CVPixelBuffer, edgeInsets: FBVideoStreamEdgeInsets) throws {
    let encoderSpecification = Self.encoderSpecification(for: configuration.format)

    let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
    let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
    // The composited frame includes the edge insets, so the NV12 pool and compression session must
    // accommodate the full output size — the same `FBVideoOutputDimensions` the composited pool uses.
    let dimensions = FBVideoOutputDimensions.calculate(
      sourceWidth: sourceWidth, sourceHeight: sourceHeight,
      scaleFactor: configuration.scaleFactor, edgeInsets: edgeInsets)
    let destinationWidth = dimensions.width
    let destinationHeight = dimensions.height
    if let scaleFactor = configuration.scaleFactor, scaleFactor > 0, scaleFactor < 1 {
      logger.info().log("Applying \(scaleFactor) scale from w=\(sourceWidth)/h=\(sourceHeight) to output w=\(destinationWidth)/h=\(destinationHeight)")
    }

    // Always create a VTPixelTransferSession to convert BGRA→NV12 (and scale if needed).
    // VTCompressionSession's native input format is NV12 (420v). Feeding it BGRA causes
    // an internal conversion pass. By converting explicitly we let VT pre-allocate its
    // pipeline via sourceImageBufferAttributes and avoid the implicit conversion.
    var transferSession: VTPixelTransferSession?
    let transferStatus = VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &transferSession)
    if transferStatus != noErr {
      throw FBSimulatorVideoStreamError.failedToCreatePixelTransferSession(status: transferStatus)
    }
    self.pixelTransferSession = transferSession
    self.nv12PixelBufferPool = createNV12PixelBufferPool(width: destinationWidth, height: destinationHeight)
    logger.info().log("Created BGRA→NV12 conversion pipeline at w=\(destinationWidth)/h=\(destinationHeight) (GPU via VTPixelTransferSession)")

    // Tell VTCompressionSession that it will receive NV12 IOSurface-backed buffers.
    let sourceImageBufferAttributes: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      kCVPixelBufferWidthKey as String: destinationWidth,
      kCVPixelBufferHeightKey as String: destinationHeight,
      kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
    ]

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
      imageBufferAttributes: sourceImageBufferAttributes as CFDictionary,
      compressedDataAllocator: nil,
      outputCallback: nil,
      refcon: nil,
      compressionSessionOut: &compressionSession
    )
    if status != noErr {
      throw FBSimulatorVideoStreamError.failedToStartCompressionSession(status: status)
    }
    guard let compressionSession else {
      throw FBSimulatorVideoStreamError.compressionSessionNil
    }

    // Resolve `.automatic` rate control: when neither a bitrate nor a quality was specified, target
    // a constant bits-per-pixel budget at the actual encoded size. Without an AverageBitRate the
    // low-latency hardware encoder falls back to its internal default (~2 Mbps regardless of
    // resolution), which macroblocks full-screen motion badly at retina sizes; the Quality property
    // is accepted but ignored by that encoder, so it cannot serve as the default either.
    var sessionProperties = compressionSessionProperties
    if sessionProperties[kVTCompressionPropertyKey_AverageBitRate as String] == nil,
      sessionProperties[kVTCompressionPropertyKey_Quality as String] == nil
    {
      let automaticBitRate = Self.automaticAverageBitRate(width: destinationWidth, height: destinationHeight)
      sessionProperties[kVTCompressionPropertyKey_AverageBitRate as String] = automaticBitRate
      logger.info().log("Derived automatic average bitrate \(automaticBitRate) bps for w=\(destinationWidth)/h=\(destinationHeight)")
    }

    let propertiesStatus = VTSessionSetProperties(compressionSession, propertyDictionary: sessionProperties as CFDictionary)
    if propertiesStatus != noErr {
      throw FBSimulatorVideoStreamError.failedToSetCompressionSessionProperties(status: propertiesStatus)
    }
    let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(compressionSession)
    if prepareStatus != noErr {
      throw FBSimulatorVideoStreamError.failedToPrepareCompressionSession(status: prepareStatus)
    }
    self.compressionSession = compressionSession
  }

  /// The `.automatic` rate-control budget: 4 bits per output pixel per second (≈0.08 bits/pixel per
  /// frame at a 50fps pan). Measured on the liquid-glass home screen: below ≈0.05 bpp the hardware
  /// encoder visibly macroblocks smooth gradients during full-screen motion, and it saturates around
  /// ≈14 Mbps at native retina size, so a larger budget buys little. Scales with `--scale`.
  static func automaticAverageBitRate(width: Int, height: Int) -> Int {
    width * height * 4
  }

  static func encoderSpecification(for format: FBVideoStreamFormat) -> [String: Any] {
    switch format {
    case .mjpeg(encoder: .allowSoftware):
      return [
        kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true
      ]
    case .mjpeg(encoder: .requireHardware), .minicap:
      // Low-latency rate control is a video-codec selector. Passing it to the
      // JPEG encoder makes VTCompressionSessionCreate return kVTParameterErr
      // (-12902) on macOS 26.
      return [
        kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true
      ]
    case .compressedVideo:
      return [
        kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true,
        kVTVideoEncoderSpecification_EnableLowLatencyRateControl as String: true,
      ]
    case .bgra:
      return [:]
    }
  }

  func tearDown() throws {
    if let compressionSession {
      VTCompressionSessionCompleteFrames(compressionSession, untilPresentationTimeStamp: .invalid)
      VTCompressionSessionInvalidate(compressionSession)
      self.compressionSession = nil
    }
    if let pixelTransferSession {
      VTPixelTransferSessionInvalidate(pixelTransferSession)
      self.pixelTransferSession = nil
    }
    // CVPixelBufferPool instances are ARC-managed; dropping the references releases them.
    self.scaledPixelBufferPool = nil
    self.nv12PixelBufferPool = nil
  }

  func writeEncodedFrame(
    _ pixelBuffer: CVPixelBuffer,
    frameNumber: UInt,
    timeAtFirstFrame: CFTimeInterval,
    frameDuration: CFTimeInterval,
    forceKeyFrame: Bool
  ) throws {
    guard let compressionSession else {
      throw FBSimulatorVideoStreamError.missingCompressionSession
    }

    var bufferToWrite = pixelBuffer

    let encodeStart = CFAbsoluteTimeGetCurrent()

    // Convert BGRA→NV12 (and scale if needed) in a single VTPixelTransferSession call.
    // VTCompressionSession's native input format is NV12; feeding it NV12 directly
    // avoids an internal conversion pass. When scaleFactor is set, the NV12 pool is
    // already sized to the destination dimensions, so scaling + format conversion
    // happen in one GPU pass.
    if let nv12Pool = nv12PixelBufferPool, let pixelTransferSession {
      var nv12Buffer: CVPixelBuffer?
      let returnStatus = CVPixelBufferPoolCreatePixelBuffer(nil, nv12Pool, &nv12Buffer)
      if returnStatus == kCVReturnSuccess, let nv12Buffer {
        let transferStatus = VTPixelTransferSessionTransferImage(pixelTransferSession, from: pixelBuffer, to: nv12Buffer)
        if transferStatus == noErr {
          bufferToWrite = nv12Buffer
        } else {
          logger.log("VTPixelTransferSession BGRA→NV12 failed: \(transferStatus) — falling back to BGRA input")
        }
      } else {
        logger.log("Failed to get a pixel buffer from the NV12 pool: \(returnStatus)")
      }
    }

    let time = CMTimeMakeWithSeconds(CFAbsoluteTimeGetCurrent() - timeAtFirstFrame, preferredTimescale: Int32(NSEC_PER_SEC))
    let duration = frameDuration > 0 ? CMTimeMakeWithSeconds(frameDuration, preferredTimescale: Int32(NSEC_PER_SEC)) : CMTime.invalid
    var frameProperties: [String: Any]?
    if frameNumber == 0 || forceKeyFrame {
      frameProperties = [kVTEncodeFrameOptionKey_ForceKeyFrame as String: true]
    }

    // The block-based output handler replaces the former create-time C output callback. It captures
    // the output mode and (for Minicap) this frame's number directly — no `sourceFrameRefcon`
    // round-trip and no holder object, so the `passRetained`/`takeRetainedValue` pair is gone.
    // `[weak self]` keeps the handler leak/cycle-free: the session does not retain the pusher, so a
    // strong capture here would be a retain cycle (pusher → session → handler → pusher). The handler
    // may run on a VideoToolbox thread after this call returns; `sampleBuffer` is ARC-managed and
    // mutable encoder state is either confined to the handler or guarded by `statsLock` (see the class doc).
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

    // Lock the source buffer for read-only access during the encode call. For
    // IOSurface-backed buffers this prevents the simulator from writing while
    // VTCompressionSession reads the pixel data, avoiding screen tearing.
    // VTCompressionSessionEncodeFrame captures the pixel data before returning
    // so we can unlock immediately after.
    //
    // Check the IOSurface seed before and after to detect if the surface was
    // modified during the encode (which would indicate a torn frame despite
    // the advisory lock).
    let surface = CVPixelBufferGetIOSurface(bufferToWrite)?.takeUnretainedValue()
    let seedBefore = surface.map { IOSurfaceGetSeed($0) } ?? 0
    CVPixelBufferLockBaseAddress(bufferToWrite, .readOnly)
    let status = VTCompressionSessionEncodeFrame(
      compressionSession,
      imageBuffer: bufferToWrite,
      presentationTimeStamp: time,
      duration: duration,
      frameProperties: frameProperties as CFDictionary?,
      infoFlagsOut: nil,
      outputHandler: handler
    )
    CVPixelBufferUnlockBaseAddress(bufferToWrite, .readOnly)

    // Track time spent in NV12 conversion + encode submission.
    let encodeEnd = CFAbsoluteTimeGetCurrent()
    withStats { $0.totalEncodeSubmitSeconds += (encodeEnd - encodeStart) }

    if let surface {
      let seedAfter = IOSurfaceGetSeed(surface)
      if seedAfter != seedBefore {
        withStats { $0.tornFrameCount += 1 }
      }
    }
    if status != 0 {
      throw FBSimulatorVideoStreamError.failedToCompress(status: status)
    }
  }

  func currentStats() -> FBVideoEncoderStats? {
    withStats { $0 }
  }
}
