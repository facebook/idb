/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import CoreMedia
import CoreServices
import CoreVideo
@preconcurrency import FBControlCore
import Foundation

private func pixelBufferAttributes(from pixelBuffer: CVPixelBuffer) -> [String: Any] {
  let width = CVPixelBufferGetWidth(pixelBuffer)
  let height = CVPixelBufferGetHeight(pixelBuffer)
  let frameSize = CVPixelBufferGetDataSize(pixelBuffer)
  let rowSize = CVPixelBufferGetBytesPerRow(pixelBuffer)
  let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
  let pixelFormatString = UTCreateStringForOSType(pixelFormat).takeRetainedValue() as String

  return [
    "width": width,
    "height": height,
    "row_size": rowSize,
    "frame_size": frameSize,
    "format": pixelFormatString,
  ]
}

@objc(FBDeviceVideoStream)
public class FBDeviceVideoStream: NSObject, FBVideoStream {
  let logger: any FBControlCoreLogger
  private let session: AVCaptureSession
  private let output: AVCaptureVideoDataOutput
  let writeQueue: DispatchQueue
  let startFuture: FBMutableFuture<NSNull>
  let stopFuture: FBMutableFuture<NSNull>

  var consumer: (any FBDataConsumer)?
  var pixelBufferAttributes_: [String: Any]?

  // MARK: Factory

  @objc(streamWithSession:configuration:logger:error:)
  public class func stream(withSession session: AVCaptureSession, configuration: FBVideoStreamConfiguration, logger: any FBControlCoreLogger) throws -> FBDeviceVideoStream {
    let format = configuration.format
    guard let streamType = classForConfiguration(configuration) else {
      throw FBDeviceControlError.describe("\(format) is not a valid stream format").build()
    }

    let output = AVCaptureVideoDataOutput()
    try streamType.configureVideoOutput(output, configuration: configuration)
    if !session.canAddOutput(output) {
      throw FBDeviceControlError.describe("Cannot add Data Output to session").build()
    }
    session.addOutput(output)

    if let fps = configuration.framesPerSecond {
      if #available(macOS 10.15, *) {
        guard let connection = session.connections.first else {
          throw FBDeviceControlError.describe("No capture connection available!").build()
        }
        let frameTime: Float64 = 1.0 / Float64(fps.uintValue)
        connection.videoMinFrameDuration = CMTimeMakeWithSeconds(frameTime, preferredTimescale: Int32(NSEC_PER_SEC))
      } else {
        throw FBDeviceControlError.describe("Cannot set FPS on an OS prior to 10.15").build()
      }
    }

    let writeQueue = DispatchQueue(label: "com.facebook.fbdevicecontrol.streamencoder")
    return streamType.init(session: session, output: output, writeQueue: writeQueue, logger: logger)
  }

  private class func classForConfiguration(_ configuration: FBVideoStreamConfiguration) -> FBDeviceVideoStream.Type? {
    let format = configuration.format
    switch format.type {
    case .compressedVideo:
      if format.codec?.rawValue == "h264" {
        if format.transport?.rawValue == "mpegts" {
          return FBDeviceVideoStream_H264MPEGTS.self
        }
        return FBDeviceVideoStream_H264.self
      }
      return nil
    case .MJPEG:
      return FBDeviceVideoStream_MJPEG.self
    case .minicap:
      return FBDeviceVideoStream_Minicap.self
    case .BGRA:
      return FBDeviceVideoStream_BGRA.self
    @unknown default:
      return nil
    }
  }

  class func configureVideoOutput(_ output: AVCaptureVideoDataOutput, configuration: FBVideoStreamConfiguration) throws {
    output.alwaysDiscardsLateVideoFrames = true
    output.videoSettings = [:]
  }

  // MARK: Initializers

  required init(session: AVCaptureSession, output: AVCaptureVideoDataOutput, writeQueue: DispatchQueue, logger: any FBControlCoreLogger) {
    self.session = session
    self.output = output
    self.writeQueue = writeQueue
    self.logger = logger
    self.startFuture = FBMutableFuture<NSNull>()
    self.stopFuture = FBMutableFuture<NSNull>()
    super.init()
  }

  // MARK: Public Methods

  @objc public func startStreaming(_ consumer: any FBDataConsumer) -> FBFuture<NSNull> {
    if self.consumer != nil {
      return FBDeviceControlError.describe("Cannot start streaming, a consumer is already attached").failFuture() as! FBFuture<NSNull>
    }
    self.consumer = consumer
    output.setSampleBufferDelegate(self, queue: writeQueue)
    session.startRunning()
    return unsafeBitCast(startFuture, to: FBFuture<NSNull>.self)
  }

  @objc public func stopStreaming() -> FBFuture<NSNull> {
    if consumer == nil {
      return FBDeviceControlError.describe("Cannot stop streaming, no consumer attached").failFuture() as! FBFuture<NSNull>
    }
    session.stopRunning()
    stopFuture.resolve(withResult: NSNull())
    return unsafeBitCast(stopFuture, to: FBFuture<NSNull>.self)
  }

  // MARK: Data consumption

  func consumeSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    fatalError("\(type(of: self)).\(#function) is abstract and should be overridden")
  }

  // MARK: FBiOSTargetOperation

  @objc public var completed: FBFuture<NSNull> {
    return unsafeBitCast(stopFuture, to: FBFuture<NSNull>.self).onQueue(
      writeQueue,
      respondToCancellation: {
        return self.stopStreaming()
      })
  }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension FBDeviceVideoStream: AVCaptureVideoDataOutputSampleBufferDelegate {
  public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard let consumer = self.consumer else { return }
    if !checkConsumerBufferLimit(consumer, logger) { return }
    startFuture.resolve(withResult: NSNull())
    consumeSampleBuffer(sampleBuffer)
  }

  public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    logger.log("Dropped a sample!")
  }
}

// MARK: - BGRA Subclass

private class FBDeviceVideoStream_BGRA: FBDeviceVideoStream {
  override func consumeSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    guard let consumer = self.consumer else { return }
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)

    if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
      let size = CVPixelBufferGetDataSize(pixelBuffer)
      if consumer.conforms(to: FBDataConsumerSync.self) {
        let data = Data(bytesNoCopy: baseAddress, count: size, deallocator: .none)
        consumer.consumeData(data)
      } else {
        let data = Data(bytes: baseAddress, count: size)
        consumer.consumeData(data)
      }
    } else {
      logger.log("Failed to get base address for pixel buffer")
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

    if pixelBufferAttributes_ == nil {
      let attributes = pixelBufferAttributes(from: pixelBuffer)
      pixelBufferAttributes_ = attributes
      logger.log("Mounting Surface with Attributes: \(FBCollectionInformation.oneLineDescription(from: attributes))")
    }
  }

  override class func configureVideoOutput(_ output: AVCaptureVideoDataOutput, configuration: FBVideoStreamConfiguration) throws {
    try super.configureVideoOutput(output, configuration: configuration)
    if !output.availableVideoPixelFormatTypes.contains(kCVPixelFormatType_32BGRA) {
      throw FBDeviceControlError().describe("kCVPixelFormatType_32BGRA is not a supported output type").build()
    }
    output.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
  }
}

// MARK: - H264 Subclass

private class FBDeviceVideoStream_H264: FBDeviceVideoStream {
  override func consumeSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    guard let consumer = self.consumer else { return }
    WriteFrameToAnnexBStream(sampleBuffer, nil, consumer, logger, nil)
  }
}

// MARK: - H264 MPEGTS Subclass

private class FBDeviceVideoStream_H264MPEGTS: FBDeviceVideoStream {
  override func consumeSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    guard let consumer = self.consumer else { return }
    WriteH264FrameToMPEGTSStream(sampleBuffer, nil, consumer, logger, nil)
  }
}

// MARK: - MJPEG Subclass

private class FBDeviceVideoStream_MJPEG: FBDeviceVideoStream {
  override func consumeSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    guard let consumer = self.consumer, let jpegDataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
    WriteJPEGDataToMJPEGStream(jpegDataBuffer, consumer, logger, nil)
  }

  override class func configureVideoOutput(_ output: AVCaptureVideoDataOutput, configuration: FBVideoStreamConfiguration) throws {
    try super.configureVideoOutput(output, configuration: configuration)
    output.alwaysDiscardsLateVideoFrames = true
    if !output.availableVideoCodecTypes.contains(.jpeg) {
      throw FBDeviceControlError.describe("AVVideoCodecTypeJPEG is not a supported codec type").build()
    }
    output.videoSettings = [
      AVVideoCodecKey: AVVideoCodecType.jpeg.rawValue,
      AVVideoCompressionPropertiesKey: [
        AVVideoQualityKey: 0.2
      ],
    ]
  }
}

// MARK: - Minicap Subclass

private class FBDeviceVideoStream_Minicap: FBDeviceVideoStream_MJPEG {
  private var hasSentHeader = false

  override func consumeSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    guard let consumer = self.consumer else { return }
    if !hasSentHeader {
      guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
      let dimensions = CMVideoFormatDescriptionGetDimensions(format)
      WriteMinicapHeaderToStream(UInt32(dimensions.width), UInt32(dimensions.height), consumer, logger, nil)
      hasSentHeader = true
    }
    guard let jpegDataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
    WriteJPEGDataToMinicapStream(jpegDataBuffer, consumer, logger, nil)
  }
}
