/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import CoreMedia
import CoreVideo
@preconcurrency import FBControlCore
import Foundation

/// How one stream format turns the samples an `AVCaptureVideoDataOutput` delivers into bytes for
/// the consumer: it asks the output for the sample format it wants, then frames each sample.
protocol DeviceSampleSink: AnyObject {
  /// Sets the output's `videoSettings` for this format. Throws if the output cannot produce it.
  func configure(_ output: AVCaptureVideoDataOutput) throws
  /// Frames one captured sample and writes it to `consumer`.
  func consume(_ sampleBuffer: CMSampleBuffer, to consumer: any DataConsumer, logger: any ControlCoreLogger)
}

enum DeviceSampleSinkError: Error, LocalizedError {
  case unsupportedBGRAOutput
  case unsupportedJPEGCodec

  var errorDescription: String? {
    switch self {
    case .unsupportedBGRAOutput:
      return "kCVPixelFormatType_32BGRA is not a supported output type"
    case .unsupportedJPEGCodec:
      return "AVVideoCodecTypeJPEG is not a supported codec type"
    }
  }
}

/// Raw BGRA pixel bytes, unframed.
final class BGRADeviceSampleSink: DeviceSampleSink {
  private var hasLoggedPixelBufferAttributes = false

  func configure(_ output: AVCaptureVideoDataOutput) throws {
    guard output.availableVideoPixelFormatTypes.contains(kCVPixelFormatType_32BGRA) else {
      throw DeviceSampleSinkError.unsupportedBGRAOutput
    }
    output.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
  }

  func consume(_ sampleBuffer: CMSampleBuffer, to consumer: any DataConsumer, logger: any ControlCoreLogger) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      logger.log("Failed to get base address for pixel buffer")
      return
    }
    let size = CVPixelBufferGetDataSize(pixelBuffer)
    if consumer is DataConsumerSync {
      consumer.consumeData(Data(bytesNoCopy: baseAddress, count: size, deallocator: .none))
    } else {
      consumer.consumeData(Data(bytes: baseAddress, count: size))
    }

    if !hasLoggedPixelBufferAttributes {
      hasLoggedPixelBufferAttributes = true
      let attributes: [String: Any] = [
        "width": CVPixelBufferGetWidth(pixelBuffer),
        "height": CVPixelBufferGetHeight(pixelBuffer),
        "row_size": CVPixelBufferGetBytesPerRow(pixelBuffer),
        "frame_size": size,
        "format": CVPixelBufferGetPixelFormatType(pixelBuffer).fourCharCodeString,
      ]
      logger.log("Mounting Surface with Attributes: \(CollectionInformation.oneLineDescription(from: attributes))")
    }
  }
}

/// H.264 from the device's own encoder, framed by a transport writer (Annex-B or MPEG-TS).
final class EncodedDeviceSampleSink: DeviceSampleSink {
  private let frameWriter: any EncodedFrameWriter
  private let transportName: String

  init(codec: VideoStreamCodec, transport: VideoStreamTransport) {
    self.frameWriter = transport.frameWriters(for: codec).frameWriter
    self.transportName = "\(codec.rawValue) \(transport.rawValue)"
  }

  func configure(_ output: AVCaptureVideoDataOutput) throws {}

  func consume(_ sampleBuffer: CMSampleBuffer, to consumer: any DataConsumer, logger: any ControlCoreLogger) {
    do {
      try frameWriter.write(sampleBuffer, to: consumer, logger: logger)
    } catch {
      logger.log("Failed to write \(transportName) frame: \(error)")
    }
  }
}

/// JPEG from the device's own encoder, raw frames back to back.
final class MJPEGDeviceSampleSink: DeviceSampleSink {
  private let frameWriter = MJPEGFrameWriter()

  func configure(_ output: AVCaptureVideoDataOutput) throws {
    try output.configureForJPEG()
  }

  func consume(_ sampleBuffer: CMSampleBuffer, to consumer: any DataConsumer, logger: any ControlCoreLogger) {
    guard let jpegDataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
    do {
      try frameWriter.write(jpegDataBuffer, to: consumer, logger: logger)
    } catch {
      logger.log("Failed to write MJPEG frame: \(error)")
    }
  }
}

/// JPEG from the device's own encoder in the Minicap wire format: a one-time header, then
/// length-prefixed frames.
final class MinicapDeviceSampleSink: DeviceSampleSink {
  private let frameWriter = MinicapFrameWriter()
  private var hasSentHeader = false

  func configure(_ output: AVCaptureVideoDataOutput) throws {
    try output.configureForJPEG()
  }

  func consume(_ sampleBuffer: CMSampleBuffer, to consumer: any DataConsumer, logger: any ControlCoreLogger) {
    if !hasSentHeader {
      guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
      let dimensions = CMVideoFormatDescriptionGetDimensions(format)
      frameWriter.writeHeader(width: UInt32(dimensions.width), height: UInt32(dimensions.height), to: consumer, logger: logger)
      hasSentHeader = true
    }
    guard let jpegDataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
    do {
      try frameWriter.write(jpegDataBuffer, to: consumer, logger: logger)
    } catch {
      logger.log("Failed to write Minicap frame: \(error)")
    }
  }
}

extension AVCaptureVideoDataOutput {
  /// Asks the capture output for JPEG samples at a fixed quality.
  fileprivate func configureForJPEG() throws {
    guard availableVideoCodecTypes.contains(.jpeg) else {
      throw DeviceSampleSinkError.unsupportedJPEGCodec
    }
    videoSettings = [
      AVVideoCodecKey: AVVideoCodecType.jpeg.rawValue,
      AVVideoCompressionPropertiesKey: [
        AVVideoQualityKey: 0.2
      ],
    ]
  }
}
