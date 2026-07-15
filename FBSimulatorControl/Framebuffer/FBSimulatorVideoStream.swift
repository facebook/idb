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

private enum FBSimulatorVideoStreamError: Error {
  case failedToCreatePixelTransferSession(status: OSStatus)
  case failedToStartCompressionSession(status: OSStatus)
  case compressionSessionNil
  case failedToSetCompressionSessionProperties(status: OSStatus)
  case failedToPrepareCompressionSession(status: OSStatus)
  case missingCompressionSession
  case failedToCompress(status: OSStatus)
  case startWhenStopped
  case startAlreadyStarted
  case stopWithoutConsumer
  case stopNotAttachedToSurface
  case failedToTearDownFramePusher(errorDescription: String)
  case failedToCreatePixelBufferFromSurface(status: CVReturn)
  case failedToCreatePixelBufferFromSurfaceNil
  case mountSurfaceWithoutConsumer
  case noPixelBufferForScreenshot
  case failedToCreateCGImage
  case failedToEncodePNG
}

extension FBSimulatorVideoStreamError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .failedToCreatePixelTransferSession(let status):
      return "Failed to create VTPixelTransferSession: \(status)"
    case .failedToStartCompressionSession(let status):
      return "Failed to start Compression Session \(status)"
    case .compressionSessionNil:
      return "Failed to start Compression Session (nil)"
    case .failedToSetCompressionSessionProperties(let status):
      return "Failed to set compression session properties \(status)"
    case .failedToPrepareCompressionSession(let status):
      return "Failed to prepare compression session \(status)"
    case .missingCompressionSession:
      return "No compression session"
    case .failedToCompress(let status):
      return "Failed to compress \(status)"
    case .startWhenStopped:
      return "Cannot start streaming, since streaming is stopped"
    case .startAlreadyStarted:
      return "Cannot start streaming, since streaming has already has started"
    case .stopWithoutConsumer:
      return "Cannot stop streaming, no consumer attached"
    case .stopNotAttachedToSurface:
      return "Cannot stop streaming, is not attached to a surface"
    case .failedToTearDownFramePusher(let errorDescription):
      return "Failed to tear down frame pusher: \(errorDescription)"
    case .failedToCreatePixelBufferFromSurface(let status):
      return "Failed to create Pixel Buffer from Surface with errorCode \(status)"
    case .failedToCreatePixelBufferFromSurfaceNil:
      return "Failed to create Pixel Buffer from Surface (nil)"
    case .mountSurfaceWithoutConsumer:
      return "Cannot mount surface when there is no consumer"
    case .noPixelBufferForScreenshot:
      return "No pixel buffer available for screenshot"
    case .failedToCreateCGImage:
      return "Failed to create CGImage from pixel buffer"
    case .failedToEncodePNG:
      return "Failed to encode PNG"
    }
  }
}

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

/// Frame cadence strategy for the video stream.
///
/// - `.lazy`: variable-frame-rate — a frame is pushed only when the framebuffer signals a damage
///   rect (`didReceiveDamageRect`).
/// - `.eager(framesPerSecond:)`: constant-frame-rate — a cadence `Task` pushes frames at the fixed
///   rate, and damage events are ignored (the cadence task drives pushes).
enum FBVideoStreamCadence {
  case lazy
  case eager(framesPerSecond: UInt)
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

// MARK: - VideoToolbox Output Mode

/// Selects what the VideoToolbox pusher's per-frame encode handler does with each encoded sample.
/// Replaces the former trio of global `@convention(c)` compressor callbacks — the same mapping the
/// pusher used to pick a C callback (all H264/HEVC → `.compressed`, MJPEG → `.mjpeg`,
/// Minicap → `.minicap`) now picks an enum case, dispatched inside the block-based encode handler.
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

// MARK: - Bitmap Frame Pusher

/// Writes raw BGRA pixel bytes (optionally scaled) straight through to the consumer, unframed.
final class FBSimulatorVideoStreamFramePusher_Bitmap: NSObject, FBSimulatorVideoStreamFramePusher {
  let consumer: any FBDataConsumer
  /// The scale factor between 0-1. nil for no scaling.
  let scaleFactor: Double?
  /// CV/VT types are ARC-managed in Swift; held strong, released automatically.
  var scaledPixelBufferPool: CVPixelBufferPool?
  var pixelTransferSession: VTPixelTransferSession?

  init(consumer: any FBDataConsumer, scaleFactor: Double?) {
    self.consumer = consumer
    self.scaleFactor = scaleFactor
    super.init()
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
/// VideoToolbox thread after the encode call returns, so it captures `self`. All mutable encoder
/// state (`stats`, warmup/starvation counters, `statsTimer`) is only ever touched from that handler
/// and from the owning stream's serial `writeQueue`, which submits frames one at a time (the encoder
/// is configured with `MaxFrameDelayCount: 0` and real-time low-latency rate control, so a frame's
/// handler completes before the next `writeEncodedFrame` is submitted). This mirrors the owning
/// `FBSimulatorVideoStream`, which is likewise `@unchecked Sendable`.
final class FBSimulatorVideoStreamFramePusher_VideoToolbox: NSObject, FBSimulatorVideoStreamFramePusher, @unchecked Sendable {
  let configuration: FBVideoStreamConfiguration
  let compressionSessionProperties: [String: Any]
  let videoCodec: CMVideoCodecType
  let outputMode: FBVideoToolboxOutputMode
  /// The encoded-sample sink for `.compressed` output; nil for MJPEG/Minicap, which write the JPEG
  /// block buffer directly to `consumer` in the encode handler.
  let encodedSampleConsumer: FBEncodedSampleConsumer?
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
  var statsTimer = FBPeriodicStatsTimer(interval: 5.0)

  init(
    configuration: FBVideoStreamConfiguration,
    compressionSessionProperties: [String: Any],
    videoCodec: CMVideoCodecType,
    consumer: any FBDataConsumer,
    outputMode: FBVideoToolboxOutputMode,
    encodedSampleConsumer: FBEncodedSampleConsumer?,
    logger: any FBControlCoreLogger
  ) {
    self.configuration = configuration
    self.compressionSessionProperties = compressionSessionProperties
    self.outputMode = outputMode
    self.encodedSampleConsumer = encodedSampleConsumer
    self.consumer = consumer
    self.logger = logger
    self.videoCodec = videoCodec
    super.init()
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
      if let encodedSampleConsumer {
        writeSucceeded = encodedSampleConsumer.consume(sampleBuffer, logger: logger)
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

  /// MJPEG output: write the encoded sample's JPEG block buffer straight to the MJPEG stream.
  /// Ignores encode status/flags, matching the former `MJPEGCompressorCallback`.
  private func handleMJPEGSampleBuffer(_ sampleBuffer: CMSampleBuffer?) {
    guard let sampleBuffer, let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
    var error: NSError?
    if !WriteJPEGDataToMJPEGStream(blockBuffer, consumer, logger, &error) {
      logger.log("Failed to write MJPEG frame: \(String(describing: error))")
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
        var error: NSError?
        if !WriteMinicapHeaderToStream(UInt32(dimensions.width), UInt32(dimensions.height), consumer, logger, &error) {
          logger.log("Failed to write Minicap header: \(String(describing: error))")
        }
      }
    }
    guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
    var error: NSError?
    if !WriteJPEGDataToMinicapStream(blockBuffer, consumer, logger, &error) {
      logger.log("Failed to write Minicap frame: \(String(describing: error))")
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
    if let scaleFactor = configuration.scaleFactor, scaleFactor > 0, scaleFactor < 1 {
      destinationWidth = Int(floor(scaleFactor * Double(sourceWidth)))
      destinationHeight = Int(floor(scaleFactor * Double(sourceHeight)))
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

    let propertiesStatus = VTSessionSetProperties(compressionSession, propertyDictionary: compressionSessionProperties as CFDictionary)
    if propertiesStatus != noErr {
      throw FBSimulatorVideoStreamError.failedToSetCompressionSessionProperties(status: propertiesStatus)
    }
    let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(compressionSession)
    if prepareStatus != noErr {
      throw FBSimulatorVideoStreamError.failedToPrepareCompressionSession(status: prepareStatus)
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
    // mutable encoder state is confined to the handler + the serial writeQueue (see the class doc).
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
    stats.totalEncodeSubmitSeconds += (encodeEnd - encodeStart)

    if let surface {
      let seedAfter = IOSurfaceGetSeed(surface)
      if seedAfter != seedBefore {
        stats.tornFrameCount += 1
      }
    }
    if status != 0 {
      throw FBSimulatorVideoStreamError.failedToCompress(status: status)
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
/// (`didChange`/`didReceiveDamageRect`), and every frame push. The cadence is selected by the
/// `cadence` strategy: `.lazy` pushes frames from the damage callback (variable frame rate), while
/// `.eager` runs a cadence `Task` that, at a fixed frame rate, dispatches `pushFrame` back onto
/// `writeQueue` and awaits it before sleeping until the next deadline.
// @unchecked Sendable: the ObjC original was a plain NSObject relied upon across the writeQueue and
// (in the eager cadence) the cadence task without formal Sendable guarantees; the sibling
// FBFramebuffer is likewise @unchecked Sendable.
@objc(FBSimulatorVideoStream)
public class FBSimulatorVideoStream: NSObject, FBFramebufferConsumer, FBVideoStream, @unchecked Sendable {

  // MARK: - Properties

  let framebuffer: FBFramebuffer
  let configuration: FBVideoStreamConfiguration
  let edgeInsets: FBVideoStreamEdgeInsets
  let cadence: FBVideoStreamCadence
  /// When set (recording), encoded `.compressed` frames are routed to this sink — an `FBSimulatorVideoFileWriter`
  /// — instead of being byte-framed to `consumer`. nil for streaming.
  let encodedSampleConsumerOverride: FBEncodedSampleConsumer?
  let writeQueue: DispatchQueue
  let logger: any FBControlCoreLogger

  // Lifecycle state, confined to `writeQueue`. `hasStarted` latches once the first surface mounts (a
  // stream cannot be restarted); `isStopped` latches on teardown and is the sole stop-idempotency
  // guard. `startAwaiters`/`stopAwaiters` hold continuations resumed on those transitions, so
  // `startStreaming`/`completed` can await them natively.
  private var hasStarted = false
  private var isStopped = false
  private var startAwaiters: [CheckedContinuation<Void, Error>] = []
  private var stopAwaiters: [CheckedContinuation<Void, Never>] = []

  /// The push-loop task that drives frame pushes (nil before `mountSurface` starts it). It iterates a
  /// stimulus `AsyncSequence` of `FrameTrigger`s: `FrameCadence` (the fixed-rate clock) in `.eager`
  /// mode, or `LazyFrameTriggers` (poked by the framebuffer callbacks) in `.lazy` mode.
  /// Started in `mountSurface`, cancelled in `cadenceTeardown`/`deinit`.
  private var framePusherTask: Task<Void, Never>?

  /// In `.lazy` (VFR) mode, the trigger source that the framebuffer callbacks (`didReceiveDamageRect`,
  /// `updateOverlayBuffer`) poke to drive a push through the shared loop. Created in `mountSurface`,
  /// finished in `cadenceTeardown`. Nil in `.eager` mode (the cadence clock drives pushes there).
  private var lazyTriggers: LazyFrameTriggers?

  /// CVPixelBuffer is ARC-managed; held strong and released automatically.
  var pixelBuffer: CVPixelBuffer?
  var timeAtFirstFrame: CFTimeInterval = 0
  var timeAtLastPush: CFTimeInterval = 0
  var frameNumber: UInt = 0
  var pixelBufferAttributes: [String: Any]?
  var consumer: (any FBDataConsumer)?
  var framePusher: (any FBSimulatorVideoStreamFramePusher)?
  var frameWriterContext: AnyObject?
  /// The timed-metadata (chapter) sink: the streaming transport writer, or (recording) the file
  /// writer's chapter track. Resolved in `mountSurface`, cleared in `stopStreaming`.
  var timedMetadataConsumer: (any FBTimedMetadataConsumer)?

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
  /// Static factories (rather than initializers) since they must derive the cadence strategy.
  public class func make(framebuffer: FBFramebuffer, configuration: FBVideoStreamConfiguration, logger: any FBControlCoreLogger) -> FBSimulatorVideoStream {
    make(framebuffer: framebuffer, configuration: configuration, edgeInsets: FBVideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0), logger: logger)
  }

  /// Constructs a Bitmap Stream with edge insets for overlay content.
  /// Insets extend the output frame dimensions, pushing video content inward.
  public class func make(framebuffer: FBFramebuffer, configuration: FBVideoStreamConfiguration, edgeInsets: FBVideoStreamEdgeInsets, logger: any FBControlCoreLogger) -> FBSimulatorVideoStream {
    FBSimulatorVideoStream(
      framebuffer: framebuffer,
      configuration: configuration,
      edgeInsets: edgeInsets,
      cadence: cadence(for: configuration),
      writeQueue: makeWriteQueue(),
      logger: logger)
  }

  /// Constructs a recording stream: encoded `.compressed` frames are muxed into a file via `fileWriter`
  /// rather than byte-framed to an `FBDataConsumer`. `edgeInsets` (default zero) reserves overlay bar
  /// regions exactly as on the streaming path; set `configuration.framesPerSecond` so the cadence is
  /// eager (a recorded file wants a continuous timeline even while the screen is idle).
  class func makeRecorder(framebuffer: FBFramebuffer, configuration: FBVideoStreamConfiguration, edgeInsets: FBVideoStreamEdgeInsets = FBVideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0), fileWriter: FBSimulatorVideoFileWriter, logger: any FBControlCoreLogger) -> FBSimulatorVideoStream {
    FBSimulatorVideoStream(
      framebuffer: framebuffer,
      configuration: configuration,
      edgeInsets: edgeInsets,
      cadence: cadence(for: configuration),
      writeQueue: makeWriteQueue(),
      logger: logger,
      encodedSampleConsumerOverride: fileWriter)
  }

  /// Starts a Bitmap Stream to `consumer` and returns the running handle.
  public class func start(framebuffer: FBFramebuffer, configuration: FBVideoStreamConfiguration, edgeInsets: FBVideoStreamEdgeInsets = FBVideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0), to consumer: any FBDataConsumer, logger: any FBControlCoreLogger) async throws -> FBSimulatorVideoStream {
    let stream = make(framebuffer: framebuffer, configuration: configuration, edgeInsets: edgeInsets, logger: logger)
    try await stream.startStreaming(consumer)
    return stream
  }

  /// Eager (constant-frame-rate) when a positive `framesPerSecond` is set, else lazy (variable-rate,
  /// driven by damage events).
  private class func cadence(for configuration: FBVideoStreamConfiguration) -> FBVideoStreamCadence {
    guard let framesPerSecond = configuration.framesPerSecond, framesPerSecond > 0 else {
      return .lazy
    }
    return .eager(framesPerSecond: UInt(framesPerSecond))
  }

  init(framebuffer: FBFramebuffer, configuration: FBVideoStreamConfiguration, edgeInsets: FBVideoStreamEdgeInsets, cadence: FBVideoStreamCadence, writeQueue: DispatchQueue, logger: any FBControlCoreLogger, encodedSampleConsumerOverride: FBEncodedSampleConsumer? = nil) {
    self.framebuffer = framebuffer
    self.configuration = configuration
    self.edgeInsets = edgeInsets
    self.cadence = cadence
    self.encodedSampleConsumerOverride = encodedSampleConsumerOverride
    self.writeQueue = writeQueue
    self.logger = logger
    super.init()
  }

  deinit {
    // Backstop: ensure the cadence task is cancelled if the stream is torn down without a clean
    // stopStreaming (which already ends the loop by cancelling the task). No-op in `.lazy` mode,
    // where the task is never started.
    framePusherTask?.cancel()
  }

  // MARK: - Public

  public func startStreaming(_ consumer: any FBDataConsumer) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      writeQueue.async { [self] in
        if hasStarted {
          continuation.resume(throwing: FBSimulatorVideoStreamError.startWhenStopped)
          return
        }
        if self.consumer != nil {
          continuation.resume(throwing: FBSimulatorVideoStreamError.startAlreadyStarted)
          return
        }
        self.consumer = consumer
        // Attach to the framebuffer; when a surface is already available this mounts it synchronously
        // (latching `hasStarted`), otherwise the first surface callback does.
        if !framebuffer.isConsumerAttached(self) {
          let surface = framebuffer.attach(self, on: writeQueue)
          didChange(surface)
        }
        if hasStarted {
          continuation.resume()
        } else {
          startAwaiters.append(continuation)
        }
      }
    }
  }

  public func stopStreaming() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      writeQueue.async { [self] in
        if isStopped {
          continuation.resume()
          return
        }
        guard let consumer = self.consumer else {
          continuation.resume(throwing: FBSimulatorVideoStreamError.stopWithoutConsumer)
          return
        }
        if !framebuffer.isConsumerAttached(self) {
          continuation.resume(throwing: FBSimulatorVideoStreamError.stopNotAttachedToSurface)
          return
        }
        self.consumer = nil
        framebuffer.detach(self)
        consumer.consumeEndOfFile()
        if let framePusher {
          do {
            try framePusher.tearDown()
          } catch {
            continuation.resume(throwing: FBSimulatorVideoStreamError.failedToTearDownFramePusher(errorDescription: "\(error)"))
            return
          }
        }
        frameWriterContext = nil
        timedMetadataConsumer = nil
        // Clean up overlay compositing resources (ARC-managed; dropping references releases them).
        overlayBuffer = nil
        compositedBufferPool = nil
        // Tear down the cadence machinery: cancels the push-loop task (the loop exits on
        // `Task.isCancelled`) and, in `.lazy` mode, finishes the trigger stream.
        cadenceTeardown()
        isStopped = true
        resumeStopAwaiters()
        continuation.resume()
      }
    }
  }

  /// Resume everyone awaiting completion. Must be called on `writeQueue`.
  private func resumeStopAwaiters() {
    let awaiters = stopAwaiters
    stopAwaiters = []
    for awaiter in awaiters {
      awaiter.resume()
    }
  }

  // MARK: - Private

  /// Tear down the push-loop machinery. Called on the `writeQueue` from `stopStreaming` before
  /// `stoppedFuture` is resolved. Finishes the `.lazy` trigger stream (ending its `for await`) and
  /// cancels the push-loop task — which also wakes the `.eager` loop if it is suspended in
  /// `Task.sleep`; either way the loop also exits on its next iteration once `stoppedFuture` is
  /// resolved.
  func cadenceTeardown() {
    lazyTriggers?.finish()
    lazyTriggers = nil
    framePusherTask?.cancel()
    framePusherTask = nil
  }

  // MARK: - FBFramebufferConsumer

  @objc(didChangeIOSurface:)
  public func didChange(_ surface: IOSurface?) {
    guard let surface else { return }
    try? mountSurface(surface)
    pushFrame(forceKeyFrame: false)
  }

  @objc
  public func didReceiveDamageRect() {
    // In `.lazy` (variable-frame-rate) mode, a damage event is a stimulus for the shared push loop.
    // In `.eager` (constant-frame-rate) mode, the cadence clock drives pushes, so damage is ignored.
    switch cadence {
    case .lazy:
      lazyTriggers?.signalDamage()
    case .eager:
      break
    }
  }

  // MARK: - Private (Surface)

  func mountSurface(_ surface: IOSurface) throws {
    // Make a Buffer from the Surface. The previous pixelBuffer is ARC-managed; assigning
    // releases it automatically (the ObjC code called CVPixelBufferRelease here manually).
    // CVPixelBufferCreateWithIOSurface returns a +1 buffer via an Unmanaged out-param, so we
    // take ownership with takeRetainedValue() (ARC then manages it from here).
    var unmanagedBuffer: Unmanaged<CVPixelBuffer>?
    let status = CVPixelBufferCreateWithIOSurface(nil, surface, nil, &unmanagedBuffer)
    if status != kCVReturnSuccess {
      throw FBSimulatorVideoStreamError.failedToCreatePixelBufferFromSurface(status: status)
    }
    guard let buffer = unmanagedBuffer?.takeRetainedValue() else {
      throw FBSimulatorVideoStreamError.failedToCreatePixelBufferFromSurfaceNil
    }

    guard let consumer else {
      throw FBSimulatorVideoStreamError.mountSurfaceWithoutConsumer
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
      encodedSampleConsumerOverride: encodedSampleConsumerOverride,
      logger: logger)
    try framePusher.setup(with: buffer, edgeInsets: edgeInsets)
    self.framePusher = framePusher
    if let videoToolboxPusher = framePusher as? FBSimulatorVideoStreamFramePusher_VideoToolbox {
      self.frameWriterContext = (videoToolboxPusher.encodedSampleConsumer as? FBDataConsumerEncodedSampleConsumer)?.frameWriterContext
    }

    // Resolve the timed-metadata (chapter) sink. A recording file writer that supports chapters
    // supplies its own consumer; otherwise the streaming transport writer (fMP4 emsg / MPEG-TS ID3)
    // handles markers, dropping them on transports with no metadata channel.
    if case .compressedVideo = configuration.format {
      self.timedMetadataConsumer =
        (encodedSampleConsumerOverride as? FBTimedMetadataConsumer)
        ?? FBTransportTimedMetadataConsumer(format: configuration.format, consumer: consumer, frameWriterContext: frameWriterContext)
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
    if let scaleFactor = configuration.scaleFactor, scaleFactor > 0, scaleFactor < 1 {
      compositedWidth = Int(floor(scaleFactor * Double(width)))
      compositedHeight = Int(floor(scaleFactor * Double(height)))
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

    // Signal that we've started, resuming anyone awaiting the initial surface mount.
    if !hasStarted {
      hasStarted = true
      let awaiters = startAwaiters
      startAwaiters = []
      for awaiter in awaiters {
        awaiter.resume()
      }
    }

    // Start the push-loop task that drives frame pushes — once; a surface re-mount just swaps
    // `pixelBuffer` for the running loop to pick up. The stimulus differs by cadence: `.eager`
    // iterates the fixed-rate `FrameCadence` clock; `.lazy` iterates `LazyFrameTriggers`, poked by
    // the framebuffer callbacks (`didReceiveDamageRect`/`updateOverlayBuffer`). Both feed the same
    // loop. `self` is captured: mutable state is confined to `writeQueue` (where the push runs) and
    // the class is `@unchecked Sendable`.
    guard framePusherTask == nil else { return }
    switch cadence {
    case let .eager(framesPerSecond):
      framePusherTask = Task { [self] in
        let stats = CadenceStats(frameIntervalNanos: NSEC_PER_SEC / UInt64(framesPerSecond), logger: logger)
        await runFramePushLoop(stimulus: FrameCadence(framesPerSecond: framesPerSecond, logger: logger), stats: stats)
      }
    case .lazy:
      let triggers = LazyFrameTriggers()
      lazyTriggers = triggers
      framePusherTask = Task { [self] in
        await runFramePushLoop(stimulus: triggers, stats: nil)
      }
    }
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
  public class func compressionSessionProperties(for configuration: FBVideoStreamConfiguration, callerProperties: [String: Any]) -> [String: Any] {
    var derived: [String: Any] = [
      kVTCompressionPropertyKey_RealTime as String: true,
      kVTCompressionPropertyKey_AllowFrameReordering as String: false,
      kVTCompressionPropertyKey_MaxFrameDelayCount as String: 0,
    ]

    switch configuration.rateControl {
    case let .bitrate(bitrate):
      // Explicit bitrate: AverageBitRate is in bits/sec
      derived[kVTCompressionPropertyKey_AverageBitRate as String] = bitrate
    case let .quality(quality):
      // Constant-quality mode
      derived[kVTCompressionPropertyKey_Quality as String] = quality
    }

    for (key, value) in callerProperties {
      derived[key] = value
    }
    derived[kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration as String] = configuration.keyFrameRate
    if case let .compressedVideo(codec, _) = configuration.format {
      switch codec {
      case .h264:
        derived[kVTCompressionPropertyKey_ProfileLevel as String] = kVTProfileLevel_H264_Baseline_AutoLevel as String
        derived[kVTCompressionPropertyKey_H264EntropyMode as String] = kVTH264EntropyMode_CAVLC as String
        if #available(macOS 12.1, *) {
          derived[kVTCompressionPropertyKey_ProfileLevel as String] = kVTProfileLevel_H264_High_AutoLevel as String
          derived[kVTCompressionPropertyKey_H264EntropyMode as String] = kVTH264EntropyMode_CABAC as String
        }
      case .hevc:
        derived[kVTCompressionPropertyKey_AllowOpenGOP as String] = false
        derived[kVTCompressionPropertyKey_ProfileLevel as String] = kVTProfileLevel_HEVC_Main_AutoLevel as String
        if #available(macOS 13.0, *) {
          derived[kVTCompressionPropertyKey_ProfileLevel as String] = kVTProfileLevel_HEVC_Main10_AutoLevel as String
        }
      }
    }
    return derived
  }

  class func framePusher(
    configuration: FBVideoStreamConfiguration,
    compressionSessionProperties: [String: Any],
    consumer: any FBDataConsumer,
    encodedSampleConsumerOverride: FBEncodedSampleConsumer?,
    logger: any FBControlCoreLogger
  ) throws -> any FBSimulatorVideoStreamFramePusher {
    let derived = Self.compressionSessionProperties(for: configuration, callerProperties: compressionSessionProperties)
    switch configuration.format {
    case let .compressedVideo(codec, transport):
      // Map (codec, transport) to the VideoToolbox codec, frame writer, and muxer context,
      // then construct the pusher once.
      let videoCodec: CMVideoCodecType
      let frameWriter: FBCompressedFrameWriter
      let frameWriterContext: AnyObject?
      switch codec {
      case .h264:
        videoCodec = kCMVideoCodecType_H264
        switch transport {
        case .fmp4:
          frameWriter = WriteH264FrameToFMP4Stream
          frameWriterContext = FBFMP4MuxerContext(hevc: false)
        case .mpegts:
          frameWriter = WriteH264FrameToMPEGTSStream
          frameWriterContext = nil
        case .annexB:
          frameWriter = WriteFrameToAnnexBStream
          frameWriterContext = nil
        }
      case .hevc:
        videoCodec = kCMVideoCodecType_HEVC
        switch transport {
        case .fmp4:
          frameWriter = WriteHEVCFrameToFMP4Stream
          frameWriterContext = FBFMP4MuxerContext(hevc: true)
        case .mpegts:
          frameWriter = WriteHEVCFrameToMPEGTSStream
          frameWriterContext = nil
        case .annexB:
          frameWriter = WriteHEVCFrameToAnnexBStream
          frameWriterContext = nil
        }
      }
      let encodedSampleConsumer: FBEncodedSampleConsumer =
        encodedSampleConsumerOverride
        ?? FBDataConsumerEncodedSampleConsumer(consumer: consumer, frameWriter: frameWriter, frameWriterContext: frameWriterContext)
      return FBSimulatorVideoStreamFramePusher_VideoToolbox(
        configuration: configuration, compressionSessionProperties: derived, videoCodec: videoCodec,
        consumer: consumer, outputMode: .compressed, encodedSampleConsumer: encodedSampleConsumer, logger: logger)
    case .mjpeg:
      return FBSimulatorVideoStreamFramePusher_VideoToolbox(
        configuration: configuration, compressionSessionProperties: derived, videoCodec: kCMVideoCodecType_JPEG,
        consumer: consumer, outputMode: .mjpeg, encodedSampleConsumer: nil, logger: logger)
    case .minicap:
      return FBSimulatorVideoStreamFramePusher_VideoToolbox(
        configuration: configuration, compressionSessionProperties: derived, videoCodec: kCMVideoCodecType_JPEG,
        consumer: consumer, outputMode: .minicap, encodedSampleConsumer: nil, logger: logger)
    case .bgra:
      return FBSimulatorVideoStreamFramePusher_Bitmap(consumer: consumer, scaleFactor: configuration.scaleFactor)
    }
  }

  /// Caller-provided compression session properties. In `.eager` mode these add the fixed frame rate
  /// (`ExpectedFrameRate`) and a long keyframe interval (`MaxKeyFrameInterval`) suited to a constant
  /// cadence; in `.lazy` mode there are none (the base, variable-frame-rate value).
  var compressionSessionProperties: [String: Any] {
    switch cadence {
    case .lazy:
      return [:]
    case let .eager(framesPerSecond):
      return [
        kVTCompressionPropertyKey_ExpectedFrameRate as String: framesPerSecond,
        kVTCompressionPropertyKey_MaxKeyFrameInterval as String: 360,
      ]
    }
  }

  // MARK: - Timed Metadata

  /// Write a timed metadata marker (chapter) at the current stream position. Routed to the
  /// `FBTimedMetadataConsumer` resolved in `mountSurface` — the streaming transport writer
  /// (MPEG-TS ID3 / fMP4 emsg) or, when recording, the file writer's chapter track. A no-op before the
  /// surface is mounted, after the stream stops, or for formats without a metadata channel.
  public func writeTimedMetadata(_ text: String) {
    timedMetadataConsumer?.writeTimedMetadata(text, logger: logger)
  }

  // MARK: - Overlay

  /// Update the overlay buffer and push a frame to encode the change.
  /// Pass nil to clear the overlay.
  ///
  /// In lazy/VFR mode: signals the push loop to encode a keyframe so the overlay change is immediately decodable.
  /// In eager/CFR mode: no extra push — the next cadence tick picks up the change without disrupting frame timing.
  public func updateOverlayBuffer(_ overlayBuffer: CVPixelBuffer?) {
    let sameReference = (overlayBuffer === self.overlayBuffer)

    // Skip atomic self-assignment when the caller is updating buffer contents in-place.
    if !sameReference {
      self.overlayBuffer = overlayBuffer
    }

    let stateDescription = overlayBuffer != nil ? (sameReference ? "contents updated" : "buffer swapped") : "cleared"
    logger.log("Overlay \(stateDescription) (frame=\(frameNumber))")

    // In lazy/VFR mode: trigger a keyframe push (through the shared loop) so overlay changes are
    // immediately decodable by consumers (e.g. ffplay) that need a keyframe to start rendering.
    // In eager/CFR mode: the push loop runs at fixed cadence and picks up the change on the next
    // tick — an extra push would disrupt frame timing.
    switch cadence {
    case .lazy:
      lazyTriggers?.signalKeyFrame()
    case .eager:
      break
    }
  }

  // MARK: - Keyframe Requests

  /// Request that the next encoded frame be a keyframe (IDR).
  /// Dispatches an extra push on the stream's write queue with the VideoToolbox
  /// `kVTEncodeFrameOptionKey_ForceKeyFrame` flag set, so a downstream consumer
  /// that has lost frames (e.g. a WebRTC viewer that has sent a PLI/FIR) can
  /// resync immediately instead of waiting for the next periodic IDR.
  ///
  /// Safe to call from any thread. A burst of calls produces a burst of
  /// keyframes — callers are expected to throttle if needed.
  public func requestKeyFrame() {
    // Dispatch onto writeQueue to match the threading expectations of
    // pushFrame(forceKeyFrame:) (every other internal caller already does this).
    writeQueue.async { [weak self] in
      self?.pushFrame(forceKeyFrame: true)
    }
  }

  // MARK: - Screenshot

  /// Capture a PNG screenshot of the current frame with overlay composited.
  public func captureCompositedScreenshot() throws -> Data {
    guard let sourceBuffer = pixelBuffer else {
      throw FBSimulatorVideoStreamError.noPixelBufferForScreenshot
    }

    // Build a CIImage, compositing the overlay if present, or applying edge inset padding.
    // Unlike pushFrame (which needs a CVPixelBuffer for the encoder), the screenshot path only
    // needs a CGImage, so we skip the intermediate buffer and go directly from the composited
    // CIImage to createCGImage.
    let ciImage = compositedImage(fromSource: sourceBuffer) ?? CIImage(cvPixelBuffer: sourceBuffer)

    let ctx = compositorCIContext ?? CIContext()
    guard let cgImage = ctx.createCGImage(ciImage, from: ciImage.extent) else {
      throw FBSimulatorVideoStreamError.failedToCreateCGImage
    }

    let pngData = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(pngData as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
      throw FBSimulatorVideoStreamError.failedToEncodePNG
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    let finalized = CGImageDestinationFinalize(dest)

    if !finalized {
      throw FBSimulatorVideoStreamError.failedToEncodePNG
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
  public func currentFramebufferStats() -> FBFramebufferStats {
    framebuffer.currentStats()
  }

  /// Total number of frames pushed to the encoder since streaming started.
  public var currentFrameNumber: UInt { frameNumber }

  /// Wall-clock time when the first frame was pushed, or 0 if not yet started.
  public var currentTimeAtFirstFrame: CFTimeInterval { timeAtFirstFrame }

  /// Wall-clock time when the first framebuffer callback was received, or 0 if not yet started.
  public var framebufferStatsStartTime: CFTimeInterval { framebuffer.statsStartTime }

  // MARK: - FBVideoStream

  public func awaitCompletion() async {
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        writeQueue.async { [self] in
          if isStopped {
            continuation.resume()
          } else {
            stopAwaiters.append(continuation)
          }
        }
      }
    } onCancel: {
      // Cancelling a completion await stops the stream (mirrors a cancellable completion signal).
      Task { [weak self] in try? await self?.stopStreaming() }
    }
  }

  // MARK: - Cadence Loop

  /// The frame push loop, shared by both cadences. It iterates a stimulus `AsyncSequence` of
  /// `FrameTrigger`s and pushes a frame for each, so the loop reads as "for each trigger, push a
  /// frame, record it". The stimulus is the only thing that differs between modes: `FrameCadence`
  /// (the drift-corrected fixed-rate clock) for `.eager`, or `LazyFrameTriggers` (fed by
  /// the damage/overlay callbacks) for `.lazy`. `stats` is provided for `.eager` (which has a frame
  /// budget) and `nil` for `.lazy` (VFR has no fixed budget).
  ///
  /// Serialization: each push — and the stream-state mutation it does (`frameNumber`, `timeAtLastPush`,
  /// the frame pusher's encoder state) — runs on the serial `writeQueue` (matching the framebuffer
  /// consumer callbacks) and is awaited before the next trigger, so pushes never overlap and mutable
  /// state stays confined to that queue, consistent with the class's `@unchecked Sendable` conformance.
  ///
  /// The loop ends when the task is cancelled (`stopStreaming`/`cadenceTeardown` cancel it, and
  /// `deinit` cancels as a backstop) or the stimulus finishes (the `.lazy` teardown finishes the
  /// stream).
  private func runFramePushLoop<Stimulus: AsyncSequence>(stimulus: Stimulus, stats: CadenceStats?) async
  where Stimulus.Element == FrameTrigger {
    var stats = stats
    do {
      // A generic `AsyncSequence` has a throwing `next()`; `FrameCadence` and `AsyncStream` are both
      // non-throwing, so the catch is unreachable in practice and exists only to satisfy `for try await`.
      for try await trigger in stimulus {
        guard !Task.isCancelled else { break }
        let pushDurationMach = await pushOnWriteQueue(forceKeyFrame: trigger.forceKeyFrame)
        stats?.record(pushDurationMach: pushDurationMach, overran: trigger.overran)
      }
    } catch {
      logger.log("Frame push loop stimulus failed: \(error)")
    }
  }

  /// Dispatch a single frame push onto the serial `writeQueue` and await its completion, returning the
  /// push duration in Mach ticks (used for cadence statistics). Keeping the measurement here lets the
  /// push loop hand the duration straight to `CadenceStats` without timing the push itself.
  private func pushOnWriteQueue(forceKeyFrame: Bool) async -> UInt64 {
    let beforePush = mach_absolute_time()
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      writeQueue.async { [self] in
        pushFrame(forceKeyFrame: forceKeyFrame)
        continuation.resume()
      }
    }
    return mach_absolute_time() - beforePush
  }
}

// MARK: - FrameTrigger / FrameCadence / LazyFrameTriggers

/// A stimulus to push one frame, produced by either cadence: the `FrameCadence` clock (eager) or
/// `LazyFrameTriggers` (lazy, fed by damage/overlay callbacks). Modelling both as the same element
/// lets a single push loop serve both modes.
struct FrameTrigger {
  /// Whether this push should force a keyframe — e.g. a `.lazy` overlay change, so consumers that
  /// need a keyframe can decode it immediately. Cadence-clock ticks never force one.
  let forceKeyFrame: Bool
  /// True when the previous push overshot its deadline (eager cadence only — always false for VFR).
  let overran: Bool
}

/// The `.lazy` (VFR) stimulus for the frame push loop: an `AsyncSequence` of `FrameTrigger`s poked by
/// the framebuffer callbacks rather than a clock. `signalDamage()` (a new framebuffer rect) and
/// `signalKeyFrame()` (an overlay change, which must be a decodable keyframe) each enqueue a trigger
/// that the shared loop consumes. Owning the stream and its keyframe state here keeps it off
/// `FBSimulatorVideoStream` and its `writeQueue`, so the callbacks simply call a method.
///
/// Triggers coalesce to the newest (`bufferingNewest(1)`): when pushes fall behind, redundant frames
/// are dropped and only the latest screen state is pushed — the correct semantics for VFR. A keyframe
/// must survive that coalescing, so it is not carried on a (droppable) trigger but held as a sticky
/// flag that `signalKeyFrame()` sets and the iterator reads-and-clears as it pulls each trigger.
// @unchecked Sendable: `pendingKeyFrame` is mutable across threads but guarded by `lock`; the stream
// and its continuation are Sendable.
final class LazyFrameTriggers: AsyncSequence, @unchecked Sendable {
  typealias Element = FrameTrigger

  private let stream: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation
  private let lock = NSLock()
  /// Whether the next pushed frame must be a keyframe. Guarded by `lock`; set by `signalKeyFrame`,
  /// read-and-cleared by the iterator, so coalescing never drops a pending keyframe.
  private var pendingKeyFrame = false

  init() {
    // The `AsyncStream` builder hands back the continuation synchronously during init, so the IUO is
    // always assigned before use. This is the pre-`makeStream` idiom (`makeStream` needs a newer
    // deployment target than our macOS 12 floor).
    // swiftlint:disable:next implicitly_unwrapped_optional
    var continuation: AsyncStream<Void>.Continuation!
    self.stream = AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) { continuation = $0 }
    self.continuation = continuation
  }

  /// Signal that the framebuffer changed — enqueue a push of the latest state.
  func signalDamage() {
    continuation.yield(())
  }

  /// Signal that the overlay changed — mark the next push a keyframe so consumers that need a keyframe
  /// can decode the change immediately, then enqueue a push.
  func signalKeyFrame() {
    lock.lock()
    pendingKeyFrame = true
    lock.unlock()
    continuation.yield(())
  }

  /// End the stream, completing the push loop's `for await`.
  func finish() {
    continuation.finish()
  }

  /// Atomically read and clear the sticky keyframe flag.
  private func takePendingKeyFrame() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let pending = pendingKeyFrame
    pendingKeyFrame = false
    return pending
  }

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(base: stream.makeAsyncIterator(), source: self)
  }

  struct AsyncIterator: AsyncIteratorProtocol {
    var base: AsyncStream<Void>.Iterator
    let source: LazyFrameTriggers

    mutating func next() async -> FrameTrigger? {
      guard await base.next() != nil else { return nil }
      return FrameTrigger(forceKeyFrame: source.takePendingKeyFrame(), overran: false)
    }
  }
}

/// A drift-corrected frame clock for `.eager` mode. Iterating it (`for await trigger in …`) suspends
/// until the next frame deadline and yields a `FrameTrigger`, so the push loop can read as just
/// "push each tick". The iterator owns all the timing — Mach-tick deadlines, the `Task.sleep` wait,
/// drift correction, and the per-deadline overrun log — and ends (returns `nil`) when the
/// surrounding `Task` is cancelled.
///
/// Note: an overrun (a push that overshoots its deadline) is detected on the *following* `next()`,
/// when the clock finds it is already past the deadline. The immediate "exceeded budget" log fires
/// at the same moment and with the same content as before; only the attribution of the overrun
/// *count* to a 5s stats window can shift by one push at a window boundary, which is immaterial.
struct FrameCadence: AsyncSequence {
  typealias Element = FrameTrigger

  let framesPerSecond: UInt
  let logger: any FBControlCoreLogger

  func makeAsyncIterator() -> Iterator {
    Iterator(framesPerSecond: framesPerSecond, logger: logger)
  }

  struct Iterator: AsyncIteratorProtocol {
    private let frameIntervalMach: UInt64
    private let frameIntervalNanos: UInt64
    private let machNumer: UInt64
    private let machDenom: UInt64
    private let logger: any FBControlCoreLogger
    private var nextTargetTime: UInt64
    private var firstTickPending = true

    init(framesPerSecond: UInt, logger: any FBControlCoreLogger) {
      let frameIntervalNanos = NSEC_PER_SEC / UInt64(framesPerSecond)
      var timebase = mach_timebase_info_data_t()
      mach_timebase_info(&timebase)
      self.machNumer = UInt64(timebase.numer)
      self.machDenom = UInt64(timebase.denom)
      self.frameIntervalNanos = frameIntervalNanos
      self.frameIntervalMach = frameIntervalNanos * UInt64(timebase.denom) / UInt64(timebase.numer)
      self.logger = logger
      self.nextTargetTime = mach_absolute_time() + self.frameIntervalMach
    }

    mutating func next() async -> FrameTrigger? {
      if Task.isCancelled {
        return nil
      }
      // The first tick fires immediately: the original loop pushes once before its first sleep.
      if firstTickPending {
        firstTickPending = false
        return FrameTrigger(forceKeyFrame: false, overran: false)
      }

      let now = mach_absolute_time()
      var overran = false
      if now < nextTargetTime {
        // Sleep until the drift-corrected deadline. Only the remaining gap is converted to nanos.
        let remainingNanos = (nextTargetTime - now) * machNumer / machDenom
        do {
          try await Task.sleep(nanoseconds: remainingNanos)
        } catch {
          return nil // cancelled while sleeping
        }
      } else {
        // Already past the deadline — the previous push overshot the frame budget.
        overran = true
        let overrunNanos = (now - nextTargetTime) * machNumer / machDenom
        logger.log(String(format: "Frame push exceeded budget by %.1f ms (budget: %.1f ms)", Double(overrunNanos) / 1e6, Double(frameIntervalNanos) / 1e6))
      }
      nextTargetTime += frameIntervalMach
      return FrameTrigger(forceKeyFrame: false, overran: overran)
    }
  }
}

// MARK: - CadenceStats

/// Accumulates eager-cadence push statistics — Welford online mean/variance of push duration plus an
/// overrun count — and logs a summary every 5 seconds. Kept out of the push loop so the loop reads
/// as just "push each tick"; `record` is called once per push.
struct CadenceStats {
  private let frameIntervalNanos: UInt64
  private let machToMs: Double
  private let statsIntervalMach: UInt64
  private let logger: any FBControlCoreLogger

  private var statsStartTime: UInt64
  private var pushCount: UInt64 = 0
  private var overrunCount: UInt64 = 0
  private var maxPushMach: UInt64 = 0
  private var pushMean = 0.0 // Welford mean (in Mach ticks)
  private var pushM2 = 0.0 // Welford M2 (sum of squared deviations)

  init(frameIntervalNanos: UInt64, logger: any FBControlCoreLogger) {
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    self.machToMs = Double(timebase.numer) / Double(timebase.denom) / 1e6
    let statsIntervalSeconds = 5.0
    self.statsIntervalMach = UInt64(statsIntervalSeconds * 1e9) * UInt64(timebase.denom) / UInt64(timebase.numer)
    self.frameIntervalNanos = frameIntervalNanos
    self.logger = logger
    self.statsStartTime = mach_absolute_time()
  }

  mutating func record(pushDurationMach: UInt64, overran: Bool) {
    pushCount += 1
    if overran {
      overrunCount += 1
    }
    if pushDurationMach > maxPushMach {
      maxPushMach = pushDurationMach
    }
    let delta = Double(pushDurationMach) - pushMean
    pushMean += delta / Double(pushCount)
    pushM2 += delta * (Double(pushDurationMach) - pushMean)

    let now = mach_absolute_time()
    guard now - statsStartTime >= statsIntervalMach else {
      return
    }
    let avgMs = pushMean * machToMs
    let maxMs = Double(maxPushMach) * machToMs
    let stddevMs = pushCount > 1 ? sqrt(pushM2 / Double(pushCount - 1)) * machToMs : 0
    let intervalSeconds = Double(now - statsStartTime) * machToMs / 1e3
    logger.info().log(
      String(
        format: "Cadence stats (%.1fs): %llu pushes, %llu overruns, push duration avg %.1f ms / max %.1f ms, jitter stddev %.1f ms (budget: %.1f ms)",
        intervalSeconds, pushCount, overrunCount, avgMs, maxMs, stddevMs, Double(frameIntervalNanos) / 1e6))

    // Reset for next interval.
    statsStartTime = now
    pushCount = 0
    overrunCount = 0
    maxPushMach = 0
    pushMean = 0
    pushM2 = 0
  }
}
