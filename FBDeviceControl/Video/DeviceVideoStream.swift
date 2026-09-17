/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import CoreMedia
@preconcurrency import FBControlCore
import Foundation

enum DeviceVideoStreamError: Error, LocalizedError {
  case invalidStreamFormat(String)
  case cannotAddDataOutput
  case noCaptureConnection
  case consumerAlreadyAttached
  case noConsumerAttached

  var errorDescription: String? {
    switch self {
    case .invalidStreamFormat(let formatDescription):
      return "\(formatDescription) is not a valid stream format"
    case .cannotAddDataOutput:
      return "Cannot add Data Output to session"
    case .noCaptureConnection:
      return "No capture connection available!"
    case .consumerAlreadyAttached:
      return "Cannot start streaming, a consumer is already attached"
    case .noConsumerAttached:
      return "Cannot stop streaming, no consumer attached"
    }
  }
}

/// Streams a physical device's screen: an `AVCaptureSession` on the device's screen-capture input
/// delivers samples in the requested `DeviceCaptureFormat` — the device encodes JPEG and H.264
/// itself — and the format's `EncodedFrameWriter` frames them for the consumer.
///
/// @unchecked Sendable: frame delivery is confined to `writeQueue` (the AVCapture delegate queue);
/// lifecycle state is guarded by `lifecycleLock`.
public final class DeviceVideoStream: NSObject, VideoStreamOperation, @unchecked Sendable {
  let logger: any ControlCoreLogger
  private let session: AVCaptureSession
  private let output: AVCaptureVideoDataOutput
  private let frameWriter: any EncodedFrameWriter
  let writeQueue: DispatchQueue
  private var hasLoggedFirstSample = false

  // Lifecycle state guarded by `lifecycleLock`: start/stop run on the caller's thread while the
  // started signal fires on `writeQueue`. `hasStarted` latches on the first delivered frame,
  // `isStopped` on stop; the awaiter lists hold continuations resumed on those transitions.
  private let lifecycleLock = NSLock()
  private var hasStarted = false
  private var isStopped = false
  private var startAwaiters: [CheckedContinuation<Void, Never>] = []
  private var stopAwaiters: [CheckedContinuation<Void, Never>] = []

  var consumer: (any DataConsumer)?

  // MARK: - Factory

  public static func stream(withSession session: AVCaptureSession, configuration: VideoStreamConfiguration, logger: any ControlCoreLogger) throws -> DeviceVideoStream {
    guard let captureFormat = captureFormat(for: configuration.format) else {
      throw DeviceVideoStreamError.invalidStreamFormat("\(configuration.format)")
    }

    let output = AVCaptureVideoDataOutput()
    output.alwaysDiscardsLateVideoFrames = true
    try captureFormat.configure(output)
    guard session.canAddOutput(output) else {
      throw DeviceVideoStreamError.cannotAddDataOutput
    }
    session.addOutput(output)

    if let fps = configuration.framesPerSecond {
      guard let connection = session.connections.first else {
        throw DeviceVideoStreamError.noCaptureConnection
      }
      connection.videoMinFrameDuration = CMTimeMakeWithSeconds(1.0 / Float64(fps), preferredTimescale: Int32(NSEC_PER_SEC))
    }

    return DeviceVideoStream(
      session: session, output: output, frameWriter: configuration.format.frameWriters().frameWriter,
      writeQueue: DispatchQueue(label: "com.facebook.fbdevicecontrol.streamencoder"), logger: logger)
  }

  /// What the capture output is asked for, or nil for a format the device cannot produce: it
  /// encodes H.264 only.
  static func captureFormat(for format: VideoStreamFormat) -> DeviceCaptureFormat? {
    switch format {
    case .compressedVideo(withCodec: .h264, transport: _):
      return .h264
    case .compressedVideo(withCodec: .hevc, transport: _):
      return nil
    case .mjpeg, .minicap:
      return .jpeg
    case .bgra:
      return .bgra
    }
  }

  init(session: AVCaptureSession, output: AVCaptureVideoDataOutput, frameWriter: any EncodedFrameWriter, writeQueue: DispatchQueue, logger: any ControlCoreLogger) {
    self.session = session
    self.output = output
    self.frameWriter = frameWriter
    self.writeQueue = writeQueue
    self.logger = logger
    super.init()
  }

  // MARK: - VideoStreamOperation

  public func startStreaming(_ consumer: any DataConsumer) async throws {
    if self.consumer != nil {
      throw DeviceVideoStreamError.consumerAlreadyAttached
    }
    self.consumer = consumer
    output.setSampleBufferDelegate(self, queue: writeQueue)
    session.startRunning()
    // Resolves once the first frame is delivered (see captureOutput).
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      registerStartAwaiter(continuation)
    }
  }

  public func stopStreaming() async throws {
    if consumer == nil {
      throw DeviceVideoStreamError.noConsumerAttached
    }
    session.stopRunning()
    if let awaiters = markStopped() {
      for awaiter in awaiters {
        awaiter.resume()
      }
    }
  }

  public func awaitCompletion() async {
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        registerStopAwaiter(continuation)
      }
    } onCancel: {
      Task { [weak self] in try? await self?.stopStreaming() }
    }
  }

  /// Frames one captured sample for the consumer. A no-op with no consumer attached.
  func consumeSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    guard let consumer else { return }
    if !hasLoggedFirstSample, let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
      hasLoggedFirstSample = true
      let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
      logger.log("First captured sample: \(dimensions.width)x\(dimensions.height) \(CMFormatDescriptionGetMediaSubType(formatDescription).fourCharCodeString)")
    }
    do {
      try frameWriter.write(sampleBuffer, to: consumer, logger: logger)
    } catch {
      logger.log("Failed to write frame: \(error)")
    }
  }

  // MARK: - Lifecycle state

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
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension DeviceVideoStream: AVCaptureVideoDataOutputSampleBufferDelegate {
  public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard let consumer else { return }
    if !consumer.hasCapacityForFrame(logger: logger) { return }
    signalStarted()
    consumeSampleBuffer(sampleBuffer)
  }

  public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    logger.log("Dropped a sample!")
  }
}
