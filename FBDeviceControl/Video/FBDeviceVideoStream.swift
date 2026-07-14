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

private func pixelBufferAttributes(from pixelBuffer: CVPixelBuffer) -> [String: Any] {
  let width = CVPixelBufferGetWidth(pixelBuffer)
  let height = CVPixelBufferGetHeight(pixelBuffer)
  let frameSize = CVPixelBufferGetDataSize(pixelBuffer)
  let rowSize = CVPixelBufferGetBytesPerRow(pixelBuffer)
  let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
  let pixelFormatString = pixelFormat.fourCharCodeString

  return [
    "width": width,
    "height": height,
    "row_size": rowSize,
    "frame_size": frameSize,
    "format": pixelFormatString,
  ]
}

// @unchecked Sendable: like FBSimulatorVideoStream, this is a plain NSObject whose frame state is
// confined to `writeQueue` (the AVCapture delegate queue), and whose lifecycle state below is guarded
// by `lifecycleLock`. The conformance lets the async completion await use a cancellation handler.
@objc(FBDeviceVideoStream)
public class FBDeviceVideoStream: NSObject, FBVideoStream, @unchecked Sendable {
  let logger: any FBControlCoreLogger
  private let session: AVCaptureSession
  private let output: AVCaptureVideoDataOutput
  let writeQueue: DispatchQueue

  // Lifecycle state guarded by `lifecycleLock`: start/stop run on the caller's thread while the
  // started signal fires on `writeQueue`. `hasStarted` latches on the first delivered frame,
  // `isStopped` on stop; the awaiter lists hold continuations resumed on those transitions.
  private let lifecycleLock = NSLock()
  private var hasStarted = false
  private var isStopped = false
  private var startAwaiters: [CheckedContinuation<Void, Never>] = []
  private var stopAwaiters: [CheckedContinuation<Void, Never>] = []

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

  // Internal (not private) so @testable tests can assert format → subclass dispatch.
  class func classForConfiguration(_ configuration: FBVideoStreamConfiguration) -> FBDeviceVideoStream.Type? {
    switch configuration.format {
    case let .compressedVideo(codec, transport):
      switch codec {
      case .h264:
        return transport == .mpegts ? FBDeviceVideoStream_H264MPEGTS.self : FBDeviceVideoStream_H264.self
      case .hevc:
        // HEVC is not yet supported on the device path.
        return nil
      }
    case .mjpeg:
      return FBDeviceVideoStream_MJPEG.self
    case .minicap:
      return FBDeviceVideoStream_Minicap.self
    case .bgra:
      return FBDeviceVideoStream_BGRA.self
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
    super.init()
  }

  // MARK: Public Methods

  public func startStreaming(_ consumer: any FBDataConsumer) async throws {
    if self.consumer != nil {
      throw FBDeviceControlError.describe("Cannot start streaming, a consumer is already attached").build()
    }
    self.consumer = consumer
    output.setSampleBufferDelegate(self, queue: writeQueue)
    session.startRunning()
    // Resolve once the first frame is delivered (see captureOutput), matching the old startFuture.
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      registerStartAwaiter(continuation)
    }
  }

  public func stopStreaming() async throws {
    if consumer == nil {
      throw FBDeviceControlError.describe("Cannot stop streaming, no consumer attached").build()
    }
    session.stopRunning()
    if let awaiters = markStopped() {
      for awaiter in awaiters {
        awaiter.resume()
      }
    }
  }

  // The lifecycle state is guarded by `lifecycleLock`, whose `lock()`/`unlock()` are unavailable from
  // async contexts, so the critical sections live in these synchronous helpers.

  private func registerStartAwaiter(_ continuation: CheckedContinuation<Void, Never>) {
    lifecycleLock.lock()
    if hasStarted {
      lifecycleLock.unlock()
      continuation.resume()
    } else {
      startAwaiters.append(continuation)
      lifecycleLock.unlock()
    }
  }

  private func registerStopAwaiter(_ continuation: CheckedContinuation<Void, Never>) {
    lifecycleLock.lock()
    if isStopped {
      lifecycleLock.unlock()
      continuation.resume()
    } else {
      stopAwaiters.append(continuation)
      lifecycleLock.unlock()
    }
  }

  /// Latch stopped and return the awaiters to resume, or nil if already stopped.
  private func markStopped() -> [CheckedContinuation<Void, Never>]? {
    lifecycleLock.lock()
    defer { lifecycleLock.unlock() }
    if isStopped {
      return nil
    }
    isStopped = true
    let awaiters = stopAwaiters
    stopAwaiters = []
    return awaiters
  }

  /// Latch the started state and resume start awaiters, on the first delivered frame.
  private func signalStarted() {
    lifecycleLock.lock()
    if hasStarted {
      lifecycleLock.unlock()
      return
    }
    hasStarted = true
    let awaiters = startAwaiters
    startAwaiters = []
    lifecycleLock.unlock()
    for awaiter in awaiters {
      awaiter.resume()
    }
  }

  // MARK: Data consumption

  func consumeSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    fatalError("\(type(of: self)).\(#function) is abstract and should be overridden")
  }

  // MARK: FBVideoStream

  public func awaitCompletion() async {
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        registerStopAwaiter(continuation)
      }
    } onCancel: {
      // Cancelling a completion await stops the stream (mirrors a cancellable completion signal).
      Task { [weak self] in try? await self?.stopStreaming() }
    }
  }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension FBDeviceVideoStream: AVCaptureVideoDataOutputSampleBufferDelegate {
  public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard let consumer = self.consumer else { return }
    if !checkConsumerBufferLimit(consumer, logger) { return }
    signalStarted()
    consumeSampleBuffer(sampleBuffer)
  }

  public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    logger.log("Dropped a sample!")
  }
}

// MARK: - BGRA Subclass

private class FBDeviceVideoStream_BGRA: FBDeviceVideoStream, @unchecked Sendable {
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

private class FBDeviceVideoStream_H264: FBDeviceVideoStream, @unchecked Sendable {
  override func consumeSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    guard let consumer = self.consumer else { return }
    WriteFrameToAnnexBStream(sampleBuffer, nil, consumer, logger, nil)
  }
}

// MARK: - H264 MPEGTS Subclass

private class FBDeviceVideoStream_H264MPEGTS: FBDeviceVideoStream, @unchecked Sendable {
  override func consumeSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    guard let consumer = self.consumer else { return }
    WriteH264FrameToMPEGTSStream(sampleBuffer, nil, consumer, logger, nil)
  }
}

// MARK: - MJPEG Subclass

private class FBDeviceVideoStream_MJPEG: FBDeviceVideoStream, @unchecked Sendable {
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

private class FBDeviceVideoStream_Minicap: FBDeviceVideoStream_MJPEG, @unchecked Sendable {
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
