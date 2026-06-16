/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreImage
import CoreMedia
import CoreServices
import CoreVideo
import FBControlCore
import Foundation
import IOSurface
import ImageIO
import Metal
import UniformTypeIdentifiers
import VideoToolbox

// FBFuture's generic surface forces `as!` / `unsafeBitCast` bridging in Swift (matching the rest of
// FBSimulatorControl, e.g. FBSimulatorVideo / FBSimulator*Commands).
// swiftlint:disable force_cast

// MARK: - Value Types

/// Edge insets that extend the output frame dimensions beyond the source framebuffer.
/// Each edge adds opaque pixels for overlay content (label bars, diagnostic stats, etc.).
public struct FBVideoStreamEdgeInsets {
  public var top: UInt
  public var bottom: UInt
  public var left: UInt
  public var right: UInt

  public init(top: UInt, bottom: UInt, left: UInt, right: UInt) {
    self.top = top
    self.bottom = bottom
    self.left = left
    self.right = right
  }
}

/// Stats tracked by the video encoder (VideoToolbox).
/// Zeroed if the stream uses a non-encoded format (e.g. bitmap/BGRA).
public struct FBVideoEncoderStats {
  public var callbackCount: UInt
  public var writeCount: UInt
  public var dropCount: UInt
  public var writeFailureCount: UInt
  public var encodeErrorCount: UInt
  public var tornFrameCount: UInt
  public var totalEncodedBytes: UInt
  public var totalEncodeSubmitSeconds: CFTimeInterval

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

// MARK: - Frame Writer

/// A Swift frame-writer function (the former `FBVideoStreamWriters` global writers, e.g.
/// `WriteFrameToAnnexBStream`). Signature mirrors the ObjC
/// `BOOL (CMSampleBufferRef, id context, id<FBDataConsumer>, id<FBControlCoreLogger>, NSError**)`.
/// Now that the writers are plain Swift functions taking an `Any?` context, this is a normal Swift
/// closure type (not `@convention(c)`). MJPEG/Minicap pushers pass `nil` and rely on their compressor
/// callback instead.
typealias FBCompressedFrameWriter =
  (
    CMSampleBuffer, Any?, any FBDataConsumer, any FBControlCoreLogger, NSErrorPointer
  ) -> Bool

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

// MARK: - Source Frame Holder

/// Holds the converted pixel buffer that backs an in-flight encode, kept alive until the
/// compressor callback fires. Passed through `VTCompressionSessionEncodeFrame`'s
/// `sourceFrameRefcon` via `Unmanaged.passRetained` and balanced by `takeRetainedValue` in the
/// callback — matching the ObjC `__bridge_retained` at encode / `__bridge_transfer` in the callback.
final class FBVideoCompressorCallbackSourceFrame {
  let frameNumber: UInt
  /// The CVPixelBuffer is ARC-managed; holding it strong keeps it alive for the encode.
  var pixelBuffer: CVPixelBuffer?

  init(pixelBuffer: CVPixelBuffer?, frameNumber: UInt) {
    self.pixelBuffer = pixelBuffer
    self.frameNumber = frameNumber
  }
}

// MARK: - Pixel Buffer Pool Helpers

private func createScaledPixelBufferPool(sourceBuffer: CVPixelBuffer, scaleFactor: NSNumber) -> CVPixelBufferPool? {
  let sourceWidth = CVPixelBufferGetWidth(sourceBuffer)
  let sourceHeight = CVPixelBufferGetHeight(sourceBuffer)

  let destinationWidth = Int(floor(scaleFactor.doubleValue * Double(sourceWidth)))
  let destinationHeight = Int(floor(scaleFactor.doubleValue * Double(sourceHeight)))

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

/// Render an `OSType` four-char code as its ASCII string (e.g. `kCVPixelFormatType_32BGRA` → "BGRA"),
/// matching the diagnostic `format` string the ObjC code produced via `UTCreateStringForOSType`
/// (which is deprecated). Falls back to the numeric value for non-printable codes.
private func fourCharCodeString(_ code: OSType) -> String {
  let bytes: [UInt8] = [
    UInt8((code >> 24) & 0xFF),
    UInt8((code >> 16) & 0xFF),
    UInt8((code >> 8) & 0xFF),
    UInt8(code & 0xFF),
  ]
  if bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) {
    return String(bytes: bytes, encoding: .ascii) ?? String(code)
  }
  return String(code)
}

private func bitmapStreamPixelBufferAttributes(from pixelBuffer: CVPixelBuffer) -> [String: Any] {
  let width = CVPixelBufferGetWidth(pixelBuffer)
  let height = CVPixelBufferGetHeight(pixelBuffer)
  let frameSize = CVPixelBufferGetDataSize(pixelBuffer)
  let rowSize = CVPixelBufferGetBytesPerRow(pixelBuffer)
  let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
  let pixelFormatString = fourCharCodeString(pixelFormat)

  var columnLeft = 0
  var columnRight = 0
  var rowsTop = 0
  var rowsBottom = 0
  CVPixelBufferGetExtendedPixels(pixelBuffer, &columnLeft, &columnRight, &rowsTop, &rowsBottom)

  return [
    "width": width,
    "height": height,
    "row_size": rowSize,
    "frame_size": frameSize,
    "padding_column_left": columnLeft,
    "padding_column_right": columnRight,
    "padding_row_top": rowsTop,
    "padding_row_bottom": rowsBottom,
    "format": pixelFormatString,
  ]
}

// MARK: - VideoToolbox Compressor Callbacks

/// `outputCallbackRefcon` is the pusher (passed unretained). `sourceFrameRefcon` is the
/// `FBVideoCompressorCallbackSourceFrame` (passed retained, consumed here via `takeRetainedValue`).
private let CompressedFrameCallback: VTCompressionOutputCallback = { outputCallbackRefCon, sourceFrameRefCon, encodeStatus, infoFlags, sampleBuffer in
  if let sourceFrameRefCon {
    _ = Unmanaged<FBVideoCompressorCallbackSourceFrame>.fromOpaque(sourceFrameRefCon).takeRetainedValue()
  }
  guard let outputCallbackRefCon, let sampleBuffer else { return }
  let pusher = Unmanaged<FBSimulatorVideoStreamFramePusher_VideoToolbox>.fromOpaque(outputCallbackRefCon).takeUnretainedValue()
  pusher.handleCompressedSampleBuffer(sampleBuffer, encodeStatus: encodeStatus, infoFlags: infoFlags)
}

private let MJPEGCompressorCallback: VTCompressionOutputCallback = { outputCallbackRefCon, sourceFrameRefCon, _, _, sampleBuffer in
  if let sourceFrameRefCon {
    _ = Unmanaged<FBVideoCompressorCallbackSourceFrame>.fromOpaque(sourceFrameRefCon).takeRetainedValue()
  }
  guard let outputCallbackRefCon, let sampleBuffer else { return }
  let pusher = Unmanaged<FBSimulatorVideoStreamFramePusher_VideoToolbox>.fromOpaque(outputCallbackRefCon).takeUnretainedValue()
  guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
  var error: NSError?
  if !WriteJPEGDataToMJPEGStream(blockBuffer, pusher.consumer, pusher.logger, &error) {
    pusher.logger.log("Failed to write MJPEG frame: \(String(describing: error))")
  }
}

private let MinicapCompressorCallback: VTCompressionOutputCallback = { outputCallbackRefCon, sourceFrameRefCon, _, _, sampleBuffer in
  var frameNumber: UInt = 0
  if let sourceFrameRefCon {
    let sourceFrame = Unmanaged<FBVideoCompressorCallbackSourceFrame>.fromOpaque(sourceFrameRefCon).takeRetainedValue()
    frameNumber = sourceFrame.frameNumber
  }
  guard let outputCallbackRefCon, let sampleBuffer else { return }
  let pusher = Unmanaged<FBSimulatorVideoStreamFramePusher_VideoToolbox>.fromOpaque(outputCallbackRefCon).takeUnretainedValue()
  if frameNumber == 0 {
    if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
      let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
      var error: NSError?
      if !WriteMinicapHeaderToStream(UInt32(dimensions.width), UInt32(dimensions.height), pusher.consumer, pusher.logger, &error) {
        pusher.logger.log("Failed to write Minicap header: \(String(describing: error))")
      }
    }
  }
  guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
  var error: NSError?
  if !WriteJPEGDataToMinicapStream(blockBuffer, pusher.consumer, pusher.logger, &error) {
    pusher.logger.log("Failed to write Minicap frame: \(String(describing: error))")
  }
}

// MARK: - Bitmap Frame Pusher

/// Writes raw BGRA pixel bytes (optionally scaled) straight through to the consumer, unframed.
final class FBSimulatorVideoStreamFramePusher_Bitmap: NSObject, FBSimulatorVideoStreamFramePusher {
  let consumer: any FBDataConsumer
  /// The scale factor between 0-1. nil for no scaling.
  let scaleFactor: NSNumber?
  /// CV/VT types are ARC-managed in Swift; held strong, released automatically.
  var scaledPixelBufferPool: CVPixelBufferPool?
  var pixelTransferSession: VTPixelTransferSession?

  init(consumer: any FBDataConsumer, scaleFactor: NSNumber?) {
    self.consumer = consumer
    self.scaleFactor = scaleFactor
    super.init()
  }

  func setup(with pixelBuffer: CVPixelBuffer, edgeInsets: FBVideoStreamEdgeInsets) throws {
    if let scaleFactor, scaleFactor.compare(0) == .orderedDescending, scaleFactor.compare(1) == .orderedAscending {
      self.scaledPixelBufferPool = createScaledPixelBufferPool(sourceBuffer: pixelBuffer, scaleFactor: scaleFactor)
      var transferSession: VTPixelTransferSession?
      let status = VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &transferSession)
      if status != noErr {
        throw FBControlCoreError.describe("Failed to create VTPixelTransferSession: \(status)").build()
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
/// directly in the compressor callback). Tracks warmup/starvation counters and periodic stats.
final class FBSimulatorVideoStreamFramePusher_VideoToolbox: NSObject, FBSimulatorVideoStreamFramePusher {
  let configuration: FBVideoStreamConfiguration
  let compressionSessionProperties: [String: Any]
  let videoCodec: CMVideoCodecType
  let compressorCallback: VTCompressionOutputCallback
  /// nil for MJPEG/Minicap, which write directly in their compressor callback.
  let frameWriter: FBCompressedFrameWriter?
  let frameWriterContext: AnyObject?
  let consumer: any FBDataConsumer
  let logger: any FBControlCoreLogger

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
  var statsTimer = FBPeriodicStatsTimerCreate(5.0)

  init(
    configuration: FBVideoStreamConfiguration,
    compressionSessionProperties: [String: Any],
    videoCodec: CMVideoCodecType,
    consumer: any FBDataConsumer,
    compressorCallback: @escaping VTCompressionOutputCallback,
    frameWriter: FBCompressedFrameWriter?,
    frameWriterContext: AnyObject?,
    logger: any FBControlCoreLogger
  ) {
    self.configuration = configuration
    self.compressionSessionProperties = compressionSessionProperties
    self.compressorCallback = compressorCallback
    self.frameWriter = frameWriter
    self.frameWriterContext = frameWriterContext
    self.consumer = consumer
    self.logger = logger
    self.videoCodec = videoCodec
    super.init()
  }

  func handleCompressedSampleBuffer(_ sampleBuffer: CMSampleBuffer?, encodeStatus: OSStatus, infoFlags: VTEncodeInfoFlags) {
    if statsTimer.startTime == 0 {
      // First call — initialize the timer.
      var unused1: CFTimeInterval = 0
      var unused2: CFTimeInterval = 0
      FBPeriodicStatsTimerTick(&statsTimer, &unused1, &unused2)
      logger.info().log("First encode callback received")
    }

    processCompressedSampleBuffer(sampleBuffer, encodeStatus: encodeStatus, infoFlags: infoFlags)

    var intervalDuration: CFTimeInterval = 0
    var totalElapsed: CFTimeInterval = 0
    if !FBPeriodicStatsTimerTick(&statsTimer, &intervalDuration, &totalElapsed) {
      return
    }

    let current = stats
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
    stats.callbackCount += 1

    if encodeStatus != noErr {
      stats.encodeErrorCount += 1
      logger.log("VideoToolbox encode error: OSStatus \(encodeStatus)")
      return
    }

    let frameDropped = infoFlags.contains(.frameDropped)
    var writeSucceeded = false
    if !frameDropped, let sampleBuffer {
      var error: NSError?
      if let frameWriter {
        writeSucceeded = frameWriter(sampleBuffer, frameWriterContext, consumer, logger, &error)
      }
      if writeSucceeded {
        if let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
          stats.totalEncodedBytes += UInt(CMBlockBufferGetDataLength(dataBuffer))
        }
      }
    }

    if frameDropped || !writeSucceeded {
      if frameDropped {
        stats.dropCount += 1
      } else {
        stats.writeFailureCount += 1
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
    stats.writeCount += 1
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

  func setup(with pixelBuffer: CVPixelBuffer, edgeInsets: FBVideoStreamEdgeInsets) throws {
    var encoderSpecification: [String: Any] = [
      kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true
    ]
    if #available(macOS 12.1, *) {
      encoderSpecification = [
        kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true,
        kVTVideoEncoderSpecification_EnableLowLatencyRateControl as String: true,
      ]
    }

    let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
    let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
    var destinationWidth = sourceWidth
    var destinationHeight = sourceHeight
    if let scaleFactor = configuration.scaleFactor, scaleFactor.compare(0) == .orderedDescending, scaleFactor.compare(1) == .orderedAscending {
      destinationWidth = Int(floor(scaleFactor.doubleValue * Double(sourceWidth)))
      destinationHeight = Int(floor(scaleFactor.doubleValue * Double(sourceHeight)))
      logger.info().log("Applying \(scaleFactor) scale from w=\(sourceWidth)/h=\(sourceHeight) to w=\(destinationWidth)/h=\(destinationHeight)")
    }
    // Add edge insets to output dimensions. The composited frame includes the insets,
    // so the NV12 pool and compression session must accommodate the full output size.
    destinationWidth += Int(edgeInsets.left + edgeInsets.right)
    destinationHeight += Int(edgeInsets.top + edgeInsets.bottom)
    // H.264 and NV12 require even dimensions.
    destinationWidth += destinationWidth % 2
    destinationHeight += destinationHeight % 2

    // Always create a VTPixelTransferSession to convert BGRA→NV12 (and scale if needed).
    // VTCompressionSession's native input format is NV12 (420v). Feeding it BGRA causes
    // an internal conversion pass. By converting explicitly we let VT pre-allocate its
    // pipeline via sourceImageBufferAttributes and avoid the implicit conversion.
    var transferSession: VTPixelTransferSession?
    let transferStatus = VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &transferSession)
    if transferStatus != noErr {
      throw FBSimulatorError.describe("Failed to create VTPixelTransferSession: \(transferStatus)").build()
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

    var compressionSession: VTCompressionSession?
    let status = VTCompressionSessionCreate(
      allocator: nil,
      width: Int32(destinationWidth),
      height: Int32(destinationHeight),
      codecType: videoCodec,
      encoderSpecification: encoderSpecification as CFDictionary,
      imageBufferAttributes: sourceImageBufferAttributes as CFDictionary,
      compressedDataAllocator: nil,
      outputCallback: compressorCallback,
      refcon: Unmanaged.passUnretained(self).toOpaque(),
      compressionSessionOut: &compressionSession
    )
    if status != noErr {
      throw FBSimulatorError.describe("Failed to start Compression Session \(status)").build()
    }
    guard let compressionSession else {
      throw FBSimulatorError.describe("Failed to start Compression Session (nil)").build()
    }

    let propertiesStatus = VTSessionSetProperties(compressionSession, propertyDictionary: compressionSessionProperties as CFDictionary)
    if propertiesStatus != noErr {
      throw FBSimulatorError.describe("Failed to set compression session properties \(propertiesStatus)").build()
    }
    let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(compressionSession)
    if prepareStatus != noErr {
      throw FBSimulatorError.describe("Failed to prepare compression session \(prepareStatus)").build()
    }
    self.compressionSession = compressionSession
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
      throw FBControlCoreError.describe("No compression session").build()
    }

    var bufferToWrite = pixelBuffer
    let sourceFrameRef = FBVideoCompressorCallbackSourceFrame(pixelBuffer: nil, frameNumber: frameNumber)

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
          sourceFrameRef.pixelBuffer = nv12Buffer
        } else {
          logger.log("VTPixelTransferSession BGRA→NV12 failed: \(transferStatus) — falling back to BGRA input")
        }
      } else {
        logger.log("Failed to get a pixel buffer from the NV12 pool: \(returnStatus)")
      }
    }

    var flags = VTEncodeInfoFlags()
    let time = CMTimeMakeWithSeconds(CFAbsoluteTimeGetCurrent() - timeAtFirstFrame, preferredTimescale: Int32(NSEC_PER_SEC))
    let duration = frameDuration > 0 ? CMTimeMakeWithSeconds(frameDuration, preferredTimescale: Int32(NSEC_PER_SEC)) : CMTime.invalid
    var frameProperties: [String: Any]?
    if frameNumber == 0 || forceKeyFrame {
      frameProperties = [kVTEncodeFrameOptionKey_ForceKeyFrame as String: true]
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
    // The sourceFrameRef is retained here (balanced by takeRetainedValue in the callback),
    // matching the ObjC __bridge_retained at encode / __bridge_transfer in the callback.
    let status = VTCompressionSessionEncodeFrame(
      compressionSession,
      imageBuffer: bufferToWrite,
      presentationTimeStamp: time,
      duration: duration,
      frameProperties: frameProperties as CFDictionary?,
      sourceFrameRefcon: Unmanaged.passRetained(sourceFrameRef).toOpaque(),
      infoFlagsOut: &flags
    )
    CVPixelBufferUnlockBaseAddress(bufferToWrite, .readOnly)

    // Track time spent in NV12 conversion + encode submission.
    let encodeEnd = CFAbsoluteTimeGetCurrent()
    stats.totalEncodeSubmitSeconds += (encodeEnd - encodeStart)

    if let surface {
      let seedAfter = IOSurfaceGetSeed(surface)
      if seedAfter != seedBefore {
        stats.tornFrameCount += 1
      }
    }
    if status != 0 {
      throw FBControlCoreError.describe("Failed to compress \(status)").build()
    }
  }

  func currentStats() -> FBVideoEncoderStats? {
    stats
  }
}

// MARK: - FBSimulatorVideoStream

/// A Video Stream of a Simulator's Framebuffer.
/// This component can be used to provide a real-time stream of a Simulator's Framebuffer.
/// This can be connected to additional software via a stream to a File Handle or Fifo.
///
/// Concurrency model: the `writeQueue` serializes start/stop, the framebuffer consumer callbacks
/// (`didChange`/`didReceiveDamageRect`), and every frame push. The Lazy subclass pushes frames from
/// those callbacks; the Eager subclass runs a cadence `Task` that, at a fixed frame rate, dispatches
/// `pushFrame` back onto `writeQueue` and awaits it before sleeping until the next deadline.
// @unchecked Sendable: the ObjC original was a plain NSObject relied upon across the writeQueue and
// (for Eager) the cadence task without formal Sendable guarantees; the sibling FBFramebuffer is
// likewise @unchecked Sendable.
@objc(FBSimulatorVideoStream)
public class FBSimulatorVideoStream: NSObject, FBFramebufferConsumer, FBVideoStream, @unchecked Sendable {

  // MARK: - Properties

  let framebuffer: FBFramebuffer
  let configuration: FBVideoStreamConfiguration
  let edgeInsets: FBVideoStreamEdgeInsets
  let writeQueue: DispatchQueue
  let logger: any FBControlCoreLogger
  let startedFuture: FBMutableFuture<NSNull>
  let stoppedFuture: FBMutableFuture<NSNull>

  /// CVPixelBuffer is ARC-managed; held strong and released automatically.
  var pixelBuffer: CVPixelBuffer?
  var timeAtFirstFrame: CFTimeInterval = 0
  var timeAtLastPush: CFTimeInterval = 0
  var frameNumber: UInt = 0
  var pixelBufferAttributes: [String: Any]?
  var consumer: (any FBDataConsumer)?
  var framePusher: (any FBSimulatorVideoStreamFramePusher)?
  var frameWriterContext: AnyObject?

  // Overlay compositing
  var overlayBuffer: CVPixelBuffer?
  var compositorCIContext: CIContext?
  var compositedBufferPool: CVPixelBufferPool?
  var compositedWidth: Int = 0
  var compositedHeight: Int = 0

  // MARK: - Initializers

  class func makeWriteQueue() -> DispatchQueue {
    DispatchQueue(label: "com.facebook.FBSimulatorControl.BitmapStream")
  }

  /// Constructs a Bitmap Stream.
  /// Bitmaps will only be written when there is a new bitmap available.
  ///
  /// Static factories (rather than initializers) since they must pick the Eager/Lazy subclass.
  /// Exposed to ObjC under the original `+streamWithFramebuffer:…` selectors.
  @objc(streamWithFramebuffer:configuration:logger:)
  public class func make(framebuffer: FBFramebuffer, configuration: FBVideoStreamConfiguration, logger: any FBControlCoreLogger) -> FBSimulatorVideoStream {
    make(framebuffer: framebuffer, configuration: configuration, edgeInsets: FBVideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0), logger: logger)
  }

  /// Constructs a Bitmap Stream with edge insets for overlay content.
  /// Insets extend the output frame dimensions, pushing video content inward.
  public class func make(framebuffer: FBFramebuffer, configuration: FBVideoStreamConfiguration, edgeInsets: FBVideoStreamEdgeInsets, logger: any FBControlCoreLogger) -> FBSimulatorVideoStream {
    let framesPerSecondNumber = configuration.framesPerSecond
    let framesPerSecond = framesPerSecondNumber?.uintValue ?? 0
    if framesPerSecondNumber != nil, framesPerSecond > 0 {
      return FBSimulatorVideoStream_Eager(
        framebuffer: framebuffer,
        configuration: configuration,
        framesPerSecond: framesPerSecond,
        edgeInsets: edgeInsets,
        writeQueue: makeWriteQueue(),
        logger: logger)
    }
    return FBSimulatorVideoStream_Lazy(
      framebuffer: framebuffer,
      configuration: configuration,
      edgeInsets: edgeInsets,
      writeQueue: makeWriteQueue(),
      logger: logger)
  }

  init(framebuffer: FBFramebuffer, configuration: FBVideoStreamConfiguration, edgeInsets: FBVideoStreamEdgeInsets, writeQueue: DispatchQueue, logger: any FBControlCoreLogger) {
    self.framebuffer = framebuffer
    self.configuration = configuration
    self.edgeInsets = edgeInsets
    self.writeQueue = writeQueue
    self.logger = logger
    self.startedFuture = FBMutableFuture<NSNull>()
    self.stoppedFuture = FBMutableFuture<NSNull>()
    super.init()
  }

  // MARK: - Public

  @objc
  public func startStreaming(_ consumer: any FBDataConsumer) -> FBFuture<NSNull> {
    let resolved: FBFuture<AnyObject> = FBFuture<AnyObject>.onQueue(
      writeQueue,
      resolve: { [weak self] () -> FBFuture<AnyObject> in
        guard let self else {
          return FBFuture(error: FBSimulatorError.describe("Stream deallocated").build())
        }
        if self.startedFuture.hasCompleted {
          return FBSimulatorError.describe("Cannot start streaming, since streaming is stopped").failFuture()
        }
        if self.consumer != nil {
          return FBSimulatorError.describe("Cannot start streaming, since streaming has already has started").failFuture()
        }
        self.consumer = consumer
        return self.attachConsumerIfNeeded() as! FBFuture<AnyObject>
      })
    return resolved.onQueue(
      writeQueue,
      fmap: { [weak self] _ -> FBFuture<AnyObject> in
        guard let self else {
          return FBFuture(error: FBSimulatorError.describe("Stream deallocated").build())
        }
        return self.startedFuture
      }) as! FBFuture<NSNull>
  }

  @objc
  public func stopStreaming() -> FBFuture<NSNull> {
    FBFuture<AnyObject>.onQueue(
      writeQueue,
      resolve: { [weak self] () -> FBFuture<AnyObject> in
        guard let self else {
          return FBFuture(error: FBSimulatorError.describe("Stream deallocated").build())
        }
        if self.stoppedFuture.hasCompleted {
          return self.stoppedFuture
        }
        guard let consumer = self.consumer else {
          return FBSimulatorError.describe("Cannot stop streaming, no consumer attached").failFuture()
        }
        if !self.framebuffer.isConsumerAttached(self) {
          return FBSimulatorError.describe("Cannot stop streaming, is not attached to a surface").failFuture()
        }
        self.consumer = nil
        self.framebuffer.detach(self)
        consumer.consumeEndOfFile()
        if let framePusher = self.framePusher {
          do {
            try framePusher.tearDown()
          } catch {
            return FBSimulatorError.describe("Failed to tear down frame pusher: \(error)").failFuture()
          }
        }
        self.frameWriterContext = nil
        // Clean up overlay compositing resources (ARC-managed; dropping references releases them).
        self.overlayBuffer = nil
        self.compositedBufferPool = nil
        // Tear down any subclass cadence machinery (the Eager subclass cancels its cadence task).
        // Resolving `stoppedFuture` below also ends the Eager cadence loop, which polls
        // `stoppedFuture.state`; cancelling additionally wakes it if it is suspended in a sleep.
        self.cadenceTeardown()
        self.stoppedFuture.resolve(withResult: NSNull())
        return self.stoppedFuture
      }) as! FBFuture<NSNull>
  }

  // MARK: - Private

  /// Tear down any subclass-specific cadence machinery. Called on the `writeQueue` from
  /// `stopStreaming` before `stoppedFuture` is resolved. No-op in the base/Lazy stream; the Eager
  /// subclass overrides this to cancel its cadence task.
  func cadenceTeardown() {}

  private func attachConsumerIfNeeded() -> FBFuture<NSNull> {
    FBFuture<AnyObject>.onQueue(
      writeQueue,
      resolve: { [weak self] () -> FBFuture<AnyObject> in
        guard let self else {
          return FBFuture(result: NSNull())
        }
        if self.framebuffer.isConsumerAttached(self) {
          self.logger.log("Already attached \(self) as a consumer")
          return FBFuture(result: NSNull())
        }
        // If we have a surface now, we can start rendering, so mount the surface.
        let surface = self.framebuffer.attach(self, on: self.writeQueue)
        self.didChange(surface)
        return FBFuture(result: NSNull())
      }) as! FBFuture<NSNull>
  }

  // MARK: - FBFramebufferConsumer

  @objc(didChangeIOSurface:)
  public func didChange(_ surface: IOSurface?) {
    guard let surface else { return }
    try? mountSurface(surface)
    pushFrame(forceKeyFrame: false)
  }

  @objc
  public func didReceiveDamageRect() {}

  // MARK: - Private (Surface)

  func mountSurface(_ surface: IOSurface) throws {
    // Make a Buffer from the Surface. The previous pixelBuffer is ARC-managed; assigning
    // releases it automatically (the ObjC code called CVPixelBufferRelease here manually).
    // CVPixelBufferCreateWithIOSurface returns a +1 buffer via an Unmanaged out-param, so we
    // take ownership with takeRetainedValue() (ARC then manages it from here).
    var unmanagedBuffer: Unmanaged<CVPixelBuffer>?
    let status = CVPixelBufferCreateWithIOSurface(nil, surface, nil, &unmanagedBuffer)
    if status != kCVReturnSuccess {
      throw FBSimulatorError.describe("Failed to create Pixel Buffer from Surface with errorCode \(status)").build()
    }
    guard let buffer = unmanagedBuffer?.takeRetainedValue() else {
      throw FBSimulatorError.describe("Failed to create Pixel Buffer from Surface (nil)").build()
    }

    guard let consumer else {
      throw FBSimulatorError.describe("Cannot mount surface when there is no consumer").build()
    }

    // Get the Attributes
    let attributes = bitmapStreamPixelBufferAttributes(from: buffer)
    logger.log("Mounting Surface with Attributes: \(FBCollectionInformation.oneLineDescription(from: attributes))")

    // Swap the pixel buffers.
    self.pixelBuffer = buffer
    self.pixelBufferAttributes = attributes

    let framePusher = try Self.framePusher(
      configuration: configuration,
      compressionSessionProperties: compressionSessionProperties,
      consumer: consumer,
      logger: logger)
    try framePusher.setup(with: buffer, edgeInsets: edgeInsets)
    self.framePusher = framePusher
    if let videoToolboxPusher = framePusher as? FBSimulatorVideoStreamFramePusher_VideoToolbox {
      self.frameWriterContext = videoToolboxPusher.frameWriterContext
    }

    // Set up overlay compositing infrastructure.
    // Metal-backed CIContext for GPU compositing — created once, reused across frames.
    if compositorCIContext == nil {
      if let device = MTLCreateSystemDefaultDevice() {
        compositorCIContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
      } else {
        compositorCIContext = CIContext(options: [.cacheIntermediates: false])
      }
    }
    // IOSurface-backed BGRA pixel buffer pool for composited output (ARC-managed).
    // Include edge insets in the pool dimensions so the composited frame has room for overlay content.
    compositedBufferPool = nil
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    var compositedWidth = width
    var compositedHeight = height
    if let scaleFactor = configuration.scaleFactor, scaleFactor.compare(0) == .orderedDescending, scaleFactor.compare(1) == .orderedAscending {
      compositedWidth = Int(floor(scaleFactor.doubleValue * Double(width)))
      compositedHeight = Int(floor(scaleFactor.doubleValue * Double(height)))
    }
    let insets = edgeInsets
    compositedWidth += Int(insets.left + insets.right)
    compositedHeight += Int(insets.top + insets.bottom)
    // H.264 and NV12 require even dimensions.
    compositedWidth += compositedWidth % 2
    compositedHeight += compositedHeight % 2
    self.compositedWidth = compositedWidth
    self.compositedHeight = compositedHeight
    let compositedPoolAttrs: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: compositedWidth,
      kCVPixelBufferHeightKey as String: compositedHeight,
      kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
    ]
    var pool: CVPixelBufferPool?
    CVPixelBufferPoolCreate(nil, nil, compositedPoolAttrs as CFDictionary, &pool)
    compositedBufferPool = pool
    if insets.top + insets.bottom + insets.left + insets.right > 0 {
      logger.info().log("Composited pool includes edge insets (t=\(insets.top) b=\(insets.bottom) l=\(insets.left) r=\(insets.right)): w=\(compositedWidth)/h=\(compositedHeight)")
    }

    // Signal that we've started
    startedFuture.resolve(withResult: NSNull())
  }

  /// Build a composited CIImage from the source pixel buffer, applying edge insets
  /// and overlaying the overlay buffer if present. Returns nil if no compositing is needed.
  func compositedImage(fromSource sourceBuffer: CVPixelBuffer) -> CIImage? {
    let overlayBuf = overlayBuffer
    let insets = edgeInsets
    let hasInsets = (insets.top + insets.bottom + insets.left + insets.right) > 0
    let needsComposite = hasInsets || (overlayBuf != nil)
    guard needsComposite, compositorCIContext != nil, compositedBufferPool != nil else {
      return nil
    }

    var sourceImage = CIImage(cvPixelBuffer: sourceBuffer)

    // Scale source to fit within the composited output (excluding insets).
    // CIImage origin is bottom-left, so after scaling we translate by (left, bottom)
    // to position the video content inside the inset frame.
    let sourceW = CVPixelBufferGetWidth(sourceBuffer)
    let targetW = compositedWidth - Int(insets.left) - Int(insets.right)
    if targetW != sourceW && sourceW > 0 {
      let s = CGFloat(targetW) / CGFloat(sourceW)
      sourceImage = sourceImage.transformed(by: CGAffineTransform(scaleX: s, y: s))
    }
    if insets.left > 0 || insets.bottom > 0 {
      sourceImage = sourceImage.transformed(by: CGAffineTransform(translationX: CGFloat(insets.left), y: CGFloat(insets.bottom)))
    }

    var result = sourceImage
    if let overlayBuf {
      let overlayImage = CIImage(cvPixelBuffer: overlayBuf)
      result = overlayImage.composited(over: sourceImage)
    }
    return result
  }

  func pushFrame(forceKeyFrame: Bool) {
    // Ensure that we have all preconditions in place before pushing.
    guard let pixelBuffer, let consumer, let framePusher else {
      return
    }
    if !checkConsumerBufferLimit(consumer, logger) {
      return
    }

    let now = CFAbsoluteTimeGetCurrent()
    let frameNumber = self.frameNumber
    if frameNumber == 0 {
      timeAtFirstFrame = now
    }
    let timeAtFirstFrame = self.timeAtFirstFrame
    let frameDuration = timeAtLastPush > 0 ? (now - timeAtLastPush) : 0
    timeAtLastPush = now

    // Composite the overlay buffer over the source frame, or apply edge inset padding.
    // When any edge inset > 0, every frame must be composited to match the output dimensions
    // of the encoder (which includes the insets). Without this, raw framebuffer pixels
    // would be fed to an encoder sized for the larger output, causing distortion.
    var bufferToEncode = pixelBuffer
    if let composited = compositedImage(fromSource: pixelBuffer), let compositedBufferPool {
      var compositedBuffer: CVPixelBuffer?
      let poolStatus = CVPixelBufferPoolCreatePixelBuffer(nil, compositedBufferPool, &compositedBuffer)
      if poolStatus == kCVReturnSuccess, let compositedBuffer {
        compositorCIContext?.render(composited, to: compositedBuffer)
        bufferToEncode = compositedBuffer
      }
    }

    // Push the Frame. The composited buffer (if any) is ARC-managed and released when
    // bufferToEncode goes out of scope (the ObjC code called CVPixelBufferRelease here).
    try? framePusher.writeEncodedFrame(
      bufferToEncode,
      frameNumber: frameNumber,
      timeAtFirstFrame: timeAtFirstFrame,
      frameDuration: frameDuration,
      forceKeyFrame: forceKeyFrame)

    // Increment frame counter
    self.frameNumber = frameNumber + 1
  }

  // MARK: - Compression Properties

  /// Builds the compression session properties dictionary for a given configuration and caller-provided properties.
  /// This is extracted for testability — the dictionary is passed to VTSessionSetProperties at stream start.
  @objc(compressionSessionPropertiesForConfiguration:callerProperties:)
  public class func compressionSessionProperties(for configuration: FBVideoStreamConfiguration, callerProperties: [String: Any]) -> [String: Any] {
    var derived: [String: Any] = [
      kVTCompressionPropertyKey_RealTime as String: true,
      kVTCompressionPropertyKey_AllowFrameReordering as String: false,
      kVTCompressionPropertyKey_MaxFrameDelayCount as String: 0,
    ]

    if configuration.rateControl.mode == .averageBitrate {
      // Explicit bitrate: AverageBitRate is in bits/sec
      derived[kVTCompressionPropertyKey_AverageBitRate as String] = configuration.rateControl.value
    } else {
      // Constant-quality mode
      derived[kVTCompressionPropertyKey_Quality as String] = configuration.rateControl.value
    }

    for (key, value) in callerProperties {
      derived[key] = value
    }
    derived[kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration as String] = configuration.keyFrameRate
    let format = configuration.format
    if format.type == .compressedVideo, format.codec == .h264 {
      derived[kVTCompressionPropertyKey_ProfileLevel as String] = kVTProfileLevel_H264_Baseline_AutoLevel as String
      derived[kVTCompressionPropertyKey_H264EntropyMode as String] = kVTH264EntropyMode_CAVLC as String
      if #available(macOS 12.1, *) {
        derived[kVTCompressionPropertyKey_ProfileLevel as String] = kVTProfileLevel_H264_High_AutoLevel as String
        derived[kVTCompressionPropertyKey_H264EntropyMode as String] = kVTH264EntropyMode_CABAC as String
      }
    }
    if format.type == .compressedVideo, format.codec == .hevc {
      derived[kVTCompressionPropertyKey_AllowOpenGOP as String] = false
      derived[kVTCompressionPropertyKey_ProfileLevel as String] = kVTProfileLevel_HEVC_Main_AutoLevel as String
      if #available(macOS 13.0, *) {
        derived[kVTCompressionPropertyKey_ProfileLevel as String] = kVTProfileLevel_HEVC_Main10_AutoLevel as String
      }
    }
    return derived
  }

  class func framePusher(
    configuration: FBVideoStreamConfiguration,
    compressionSessionProperties: [String: Any],
    consumer: any FBDataConsumer,
    logger: any FBControlCoreLogger
  ) throws -> any FBSimulatorVideoStreamFramePusher {
    let derived = Self.compressionSessionProperties(for: configuration, callerProperties: compressionSessionProperties)
    let format = configuration.format
    switch format.type {
    case .compressedVideo:
      if format.codec == .h264 {
        if format.transport == .fmp4 {
          let ctx = FBFMP4MuxerContext(hevc: false)
          return FBSimulatorVideoStreamFramePusher_VideoToolbox(
            configuration: configuration, compressionSessionProperties: derived, videoCodec: kCMVideoCodecType_H264,
            consumer: consumer, compressorCallback: CompressedFrameCallback, frameWriter: WriteH264FrameToFMP4Stream, frameWriterContext: ctx, logger: logger)
        }
        if format.transport == .mpegts {
          return FBSimulatorVideoStreamFramePusher_VideoToolbox(
            configuration: configuration, compressionSessionProperties: derived, videoCodec: kCMVideoCodecType_H264,
            consumer: consumer, compressorCallback: CompressedFrameCallback, frameWriter: WriteH264FrameToMPEGTSStream, frameWriterContext: nil, logger: logger)
        }
        return FBSimulatorVideoStreamFramePusher_VideoToolbox(
          configuration: configuration, compressionSessionProperties: derived, videoCodec: kCMVideoCodecType_H264,
          consumer: consumer, compressorCallback: CompressedFrameCallback, frameWriter: WriteFrameToAnnexBStream, frameWriterContext: nil, logger: logger)
      }
      if format.codec == .hevc {
        if format.transport == .fmp4 {
          let ctx = FBFMP4MuxerContext(hevc: true)
          return FBSimulatorVideoStreamFramePusher_VideoToolbox(
            configuration: configuration, compressionSessionProperties: derived, videoCodec: kCMVideoCodecType_HEVC,
            consumer: consumer, compressorCallback: CompressedFrameCallback, frameWriter: WriteHEVCFrameToFMP4Stream, frameWriterContext: ctx, logger: logger)
        }
        if format.transport == .mpegts {
          return FBSimulatorVideoStreamFramePusher_VideoToolbox(
            configuration: configuration, compressionSessionProperties: derived, videoCodec: kCMVideoCodecType_HEVC,
            consumer: consumer, compressorCallback: CompressedFrameCallback, frameWriter: WriteHEVCFrameToMPEGTSStream, frameWriterContext: nil, logger: logger)
        }
        return FBSimulatorVideoStreamFramePusher_VideoToolbox(
          configuration: configuration, compressionSessionProperties: derived, videoCodec: kCMVideoCodecType_HEVC,
          consumer: consumer, compressorCallback: CompressedFrameCallback, frameWriter: WriteHEVCFrameToAnnexBStream, frameWriterContext: nil, logger: logger)
      }
      throw FBControlCoreError.describe("Unsupported codec '\(String(describing: format.codec))'").build()
    case .mjpeg:
      return FBSimulatorVideoStreamFramePusher_VideoToolbox(
        configuration: configuration, compressionSessionProperties: derived, videoCodec: kCMVideoCodecType_JPEG,
        consumer: consumer, compressorCallback: MJPEGCompressorCallback, frameWriter: nil, frameWriterContext: nil, logger: logger)
    case .minicap:
      return FBSimulatorVideoStreamFramePusher_VideoToolbox(
        configuration: configuration, compressionSessionProperties: derived, videoCodec: kCMVideoCodecType_JPEG,
        consumer: consumer, compressorCallback: MinicapCompressorCallback, frameWriter: nil, frameWriterContext: nil, logger: logger)
    case .bgra:
      return FBSimulatorVideoStreamFramePusher_Bitmap(consumer: consumer, scaleFactor: configuration.scaleFactor)
    @unknown default:
      throw FBControlCoreError.describe("Unsupported format type \(format.type.rawValue)").build()
    }
  }

  /// Caller-provided compression session properties. Overridden by the Eager subclass.
  var compressionSessionProperties: [String: Any] { [:] }

  // MARK: - Timed Metadata

  /// Write a timed metadata marker (chapter) to the stream.
  /// Dispatches to the appropriate transport mechanism (MPEG-TS ID3, fMP4 emsg).
  /// Logs and drops if the transport does not support timed metadata.
  @objc
  public func writeTimedMetadata(_ text: String) {
    let format = configuration.format
    if format.type != .compressedVideo {
      return
    }
    guard let consumer else { return }

    if format.transport == .mpegts {
      FBMPEGTSEnableMetadataStream()
      FBMPEGTSWriteTimedMetadata(text, consumer)
    } else if format.transport == .fmp4 {
      if let ctx = frameWriterContext as? FBFMP4MuxerContext {
        FBFMP4WriteEmsgBox(ctx, text, consumer)
      }
    } else {
      logger.log("writeTimedMetadata: not supported for transport '\(String(describing: format.transport))', dropping")
    }
  }

  // MARK: - Overlay

  /// Update the overlay buffer and push a frame to encode the change.
  /// Pass nil to clear the overlay.
  ///
  /// In lazy/VFR mode: dispatches pushFrame on the write queue so overlay changes are encoded immediately.
  /// In eager/CFR mode: no extra push — the next cadence tick picks up the change without disrupting frame timing.
  @objc
  public func updateOverlayBuffer(_ overlayBuffer: CVPixelBuffer?) {
    let sameReference = (overlayBuffer === self.overlayBuffer)

    // Skip atomic self-assignment when the caller is updating buffer contents in-place.
    if !sameReference {
      self.overlayBuffer = overlayBuffer
    }

    let stateDescription = overlayBuffer != nil ? (sameReference ? "contents updated" : "buffer swapped") : "cleared"
    logger.log("Overlay \(stateDescription) (frame=\(frameNumber))")

    // In lazy/VFR mode: force a keyframe push so overlay changes are immediately
    // decodable by consumers (e.g. ffplay) that need a keyframe to start rendering.
    // In eager/CFR mode: the push loop runs at fixed cadence and picks up the change
    // on the next tick — an extra push would disrupt frame timing.
    if self is FBSimulatorVideoStream_Lazy {
      writeQueue.async { [weak self] in
        self?.pushFrame(forceKeyFrame: true)
      }
    }
  }

  // MARK: - Screenshot

  /// Capture a PNG screenshot of the current frame with overlay composited.
  /// Exposed to ObjC as `captureCompositedScreenshotWithError:`; Swift callers use `try`.
  @objc(captureCompositedScreenshotWithError:)
  public func captureCompositedScreenshot() throws -> Data {
    guard let sourceBuffer = pixelBuffer else {
      throw FBSimulatorError.describe("No pixel buffer available for screenshot").build()
    }

    // Build a CIImage, compositing the overlay if present, or applying edge inset padding.
    // Unlike pushFrame (which needs a CVPixelBuffer for the encoder), the screenshot path only
    // needs a CGImage, so we skip the intermediate buffer and go directly from the composited
    // CIImage to createCGImage.
    let ciImage = compositedImage(fromSource: sourceBuffer) ?? CIImage(cvPixelBuffer: sourceBuffer)

    let ctx = compositorCIContext ?? CIContext()
    guard let cgImage = ctx.createCGImage(ciImage, from: ciImage.extent) else {
      throw FBSimulatorError.describe("Failed to create CGImage from pixel buffer").build()
    }

    let pngData = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(pngData as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
      throw FBSimulatorError.describe("Failed to encode PNG").build()
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    let finalized = CGImageDestinationFinalize(dest)

    if !finalized {
      throw FBSimulatorError.describe("Failed to encode PNG").build()
    }

    return pngData as Data
  }

  // MARK: - Stats

  /// Returns a snapshot of the current video encoder stats.
  /// Returns a zeroed struct if the stream uses a non-encoded format (e.g. bitmap/BGRA).
  public func currentEncoderStats() -> FBVideoEncoderStats {
    if let pusher = framePusher, let stats = pusher.currentStats() {
      return stats
    }
    return FBVideoEncoderStats()
  }

  /// Returns a snapshot of the current framebuffer stats (from the underlying FBFramebuffer).
  @objc
  public func currentFramebufferStats() -> FBFramebufferStats {
    framebuffer.currentStats()
  }

  /// Total number of frames pushed to the encoder since streaming started.
  @objc
  public var currentFrameNumber: UInt { frameNumber }

  /// Wall-clock time when the first frame was pushed, or 0 if not yet started.
  @objc
  public var currentTimeAtFirstFrame: CFTimeInterval { timeAtFirstFrame }

  /// Wall-clock time when the first framebuffer callback was received, or 0 if not yet started.
  @objc
  public var framebufferStatsStartTime: CFTimeInterval { framebuffer.statsStartTime }

  // MARK: - FBiOSTargetOperation

  @objc
  public var completed: FBFuture<NSNull> {
    let mutable = FBMutableFuture<NSNull>()
    _ = mutable.resolve(from: stoppedFuture)
    return unsafeBitCast(
      mutable.onQueue(
        writeQueue,
        respondToCancellation: { [weak self] in
          guard let self else { return FBFuture<NSNull>.empty() }
          return self.stopStreaming()
        }),
      to: FBFuture<NSNull>.self)
  }
}

// MARK: - FBSimulatorVideoStream_Lazy

/// Variable-frame-rate stream: pushes a frame only when the framebuffer signals a damage rect.
final class FBSimulatorVideoStream_Lazy: FBSimulatorVideoStream, @unchecked Sendable {

  @objc
  public override func didReceiveDamageRect() {
    pushFrame(forceKeyFrame: false)
  }
}

// MARK: - FBSimulatorVideoStream_Eager

/// Constant-frame-rate stream: pushes frames at a fixed cadence driven by a Swift `Task`.
///
/// Concurrency model: `mountSurface` starts a detached cadence `Task` (`framePusherTask`) running
/// `runFramePushLoop`, a drift-corrected loop that suspends between ticks with
/// `Task.sleep(nanoseconds:)` instead of blocking a dedicated `Thread` with `mach_wait_until`.
/// Timing is still measured in Mach ticks (`mach_absolute_time()`) to preserve the original
/// drift-correction exactly — only the wait mechanism changes from a blocking thread to a
/// suspending task. The loop runs while `stoppedFuture` is running and the task is not cancelled.
///
/// Serialization: the actual frame push (`pushFrame`) — and all the stream-state mutation it does
/// (`frameNumber`, `timeAtLastPush`, the frame pusher's encoder state) — must stay serialized on
/// the existing serial `writeQueue`, which also runs the framebuffer consumer callbacks. The async
/// loop therefore dispatches each `pushFrame(forceKeyFrame: false)` onto `writeQueue` and awaits
/// its completion (via a checked continuation) before measuring push duration and sleeping. This
/// keeps the cadence single-in-flight (no overlapping pushes) and confines all mutable state to
/// `writeQueue`, consistent with the class's `@unchecked Sendable` conformance.
///
/// The task is cancelled from the `stopStreaming` teardown path (which resolves `stoppedFuture`,
/// ending the loop condition) and on `deinit` as a backstop.
final class FBSimulatorVideoStream_Eager: FBSimulatorVideoStream, @unchecked Sendable {

  let framesPerSecond: UInt
  private var framePusherTask: Task<Void, Never>?

  init(framebuffer: FBFramebuffer, configuration: FBVideoStreamConfiguration, framesPerSecond: UInt, edgeInsets: FBVideoStreamEdgeInsets, writeQueue: DispatchQueue, logger: any FBControlCoreLogger) {
    self.framesPerSecond = framesPerSecond
    super.init(framebuffer: framebuffer, configuration: configuration, edgeInsets: edgeInsets, writeQueue: writeQueue, logger: logger)
  }

  deinit {
    // Backstop: ensure the cadence task is cancelled if the stream is torn down without a
    // clean stopStreaming (which already ends the loop by resolving stoppedFuture).
    framePusherTask?.cancel()
  }

  override var compressionSessionProperties: [String: Any] {
    [
      kVTCompressionPropertyKey_ExpectedFrameRate as String: framesPerSecond,
      kVTCompressionPropertyKey_MaxKeyFrameInterval as String: 360,
    ]
  }

  override func mountSurface(_ surface: IOSurface) throws {
    try super.mountSurface(surface)

    // Start the cadence task in place of the former dedicated Thread. `self` is captured: the
    // class confines its mutable state to `writeQueue` (where the push actually runs) and is
    // `@unchecked Sendable`, consistent with capturing it here.
    framePusherTask = Task { [self] in
      await runFramePushLoop()
    }
  }

  /// Cancel the cadence task when streaming stops. Runs on the `writeQueue` (called from
  /// `stopStreaming`). Cancellation wakes the loop if it is suspended in `Task.sleep`; the loop
  /// also exits on the next iteration once `stoppedFuture` is resolved.
  override func cadenceTeardown() {
    framePusherTask?.cancel()
    framePusherTask = nil
  }

  private func runFramePushLoop() async {
    let fps = framesPerSecond
    let frameIntervalNanos = NSEC_PER_SEC / UInt64(fps)

    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    let frameIntervalMach = frameIntervalNanos * UInt64(timebase.denom) / UInt64(timebase.numer)

    // Cadence stats (Welford's online algorithm for variance).
    let statsIntervalSeconds = 5.0
    let statsIntervalMach = UInt64(statsIntervalSeconds * 1e9) * UInt64(timebase.denom) / UInt64(timebase.numer)
    var statsStartTime = mach_absolute_time()
    var pushCount: UInt64 = 0
    var overrunCount: UInt64 = 0
    var maxPushMach: UInt64 = 0
    var pushMean = 0.0 // Welford mean (in Mach ticks)
    var pushM2 = 0.0 // Welford M2 (sum of squared deviations)

    var nextTargetTime = mach_absolute_time() + frameIntervalMach
    while stoppedFuture.state == .running && !Task.isCancelled {
      let beforePush = mach_absolute_time()
      // Serialize the push (and the stream-state mutation it performs) onto the writeQueue,
      // matching the framebuffer consumer callbacks, and await its completion before sleeping.
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        writeQueue.async { [self] in
          pushFrame(forceKeyFrame: false)
          continuation.resume()
        }
      }
      let afterPush = mach_absolute_time()

      // Track push duration stats.
      let pushDuration = afterPush - beforePush
      pushCount += 1
      if pushDuration > maxPushMach {
        maxPushMach = pushDuration
      }
      let delta = Double(pushDuration) - pushMean
      pushMean += delta / Double(pushCount)
      pushM2 += delta * (Double(pushDuration) - pushMean)

      // Sleep until the next drift-corrected deadline, or log an overrun if we are already past it.
      // Timing stays in Mach ticks for drift-correction; only the remaining gap is converted to
      // nanoseconds for Task.sleep (the macOS 12 deployment target rules out ContinuousClock).
      if afterPush < nextTargetTime {
        let remainingMach = nextTargetTime - afterPush
        let remainingNanos = remainingMach * UInt64(timebase.numer) / UInt64(timebase.denom)
        do {
          try await Task.sleep(nanoseconds: remainingNanos)
        } catch {
          // Cancelled while sleeping — exit the loop.
          break
        }
      } else {
        overrunCount += 1
        let overrunNanos = (afterPush - nextTargetTime) * UInt64(timebase.numer) / UInt64(timebase.denom)
        logger.log(String(format: "Frame push exceeded budget by %.1f ms (budget: %.1f ms)", Double(overrunNanos) / 1e6, Double(frameIntervalNanos) / 1e6))
      }
      nextTargetTime += frameIntervalMach

      // Periodic cadence stats.
      if afterPush - statsStartTime >= statsIntervalMach {
        let toMs = Double(timebase.numer) / Double(timebase.denom) / 1e6
        let avgMs = pushMean * toMs
        let maxMs = Double(maxPushMach) * toMs
        let stddevMs = pushCount > 1 ? sqrt(pushM2 / Double(pushCount - 1)) * toMs : 0
        let intervalSeconds = Double(afterPush - statsStartTime) * Double(timebase.numer) / Double(timebase.denom) / 1e9
        logger.info().log(
          String(
            format: "Cadence stats (%.1fs): %llu pushes, %llu overruns, push duration avg %.1f ms / max %.1f ms, jitter stddev %.1f ms (budget: %.1f ms)",
            intervalSeconds, pushCount, overrunCount, avgMs, maxMs, stddevMs, Double(frameIntervalNanos) / 1e6))

        // Reset for next interval.
        statsStartTime = afterPush
        pushCount = 0
        overrunCount = 0
        maxPushMach = 0
        pushMean = 0
        pushM2 = 0
      }
    }
  }
}
