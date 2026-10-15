/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import CoreMedia
import CoreVideo
import FBControlCore
import FBVideoCore
import Foundation
import os

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
/// @unchecked Sendable: frame delivery is confined to `writeQueue` (the AVCapture delegate queue),
/// which is the only place `frameWriter` and `hasLoggedFirstSample` are touched. `consumer` is
/// written once by `attach`, before the session starts delivering, and read on `writeQueue` after.
/// The phase, which start/stop drive from the caller's thread while the first frame lands on
/// `writeQueue`, lives under `lifecycle`.
public final class DeviceVideoStream: VideoStreamOperation, @unchecked Sendable {
  let logger: any ControlCoreLogger
  private let session: AVCaptureSession
  private let output: AVCaptureVideoDataOutput
  private let frameWriter: any EncodedFrameWriter
  let writeQueue: DispatchQueue
  private var hasLoggedFirstSample = false
  private var relay: CaptureRelay?
  private(set) var consumer: (any DataConsumer)?

  /// Where the stream is in its life. `starting` holds whoever is waiting for the first frame;
  /// `awaitCompletion` callers are held separately since completion can be awaited from any phase.
  private struct Lifecycle {
    enum Phase {
      case idle
      case starting(awaiters: [CheckedContinuation<Void, Never>])
      case streaming
      case stopped
    }

    var phase: Phase = .idle
    var completionAwaiters: [CheckedContinuation<Void, Never>] = []
  }

  private let lifecycle = OSAllocatedUnfairLock(initialState: Lifecycle())

  // MARK: - Initializers

  /// Adds a data output to `session` that captures in the configured format and frame rate.
  public convenience init(session: AVCaptureSession, configuration: VideoStreamConfiguration, logger: any ControlCoreLogger) throws {
    guard let captureFormat = DeviceCaptureFormat(configuration.format) else {
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

    self.init(
      session: session, output: output, frameWriter: configuration.format.frameWriters().frameWriter,
      writeQueue: DispatchQueue(label: "com.facebook.fbdevicecontrol.streamencoder"), logger: logger)
  }

  init(session: AVCaptureSession, output: AVCaptureVideoDataOutput, frameWriter: any EncodedFrameWriter, writeQueue: DispatchQueue, logger: any ControlCoreLogger) {
    self.session = session
    self.output = output
    self.frameWriter = frameWriter
    self.writeQueue = writeQueue
    self.logger = logger
  }

  // MARK: - VideoStreamOperation

  public func startStreaming(_ consumer: any DataConsumer) async throws {
    try attach(consumer)
    let relay = CaptureRelay(
      onSample: { [weak self] sampleBuffer in self?.deliver(sampleBuffer) },
      onDrop: { [weak self] in self?.logger.log("Dropped a sample!") })
    self.relay = relay
    output.setSampleBufferDelegate(relay, queue: writeQueue)
    session.startRunning()
    // Resolves once the first frame is delivered (see `deliver`).
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let resumeNow = lifecycle.withLock { state -> Bool in
        guard case let .starting(awaiters) = state.phase else {
          return true
        }
        state.phase = .starting(awaiters: awaiters + [continuation])
        return false
      }
      if resumeNow {
        continuation.resume()
      }
    }
  }

  public func stopStreaming() async throws {
    let awaiters = try lifecycle.withLock { state -> [CheckedContinuation<Void, Never>] in
      switch state.phase {
      case .idle:
        throw DeviceVideoStreamError.noConsumerAttached
      case .stopped:
        return []
      case .starting, .streaming:
        state.phase = .stopped
        defer { state.completionAwaiters = [] }
        return state.completionAwaiters
      }
    }
    session.stopRunning()
    for awaiter in awaiters {
      awaiter.resume()
    }
  }

  public func awaitCompletion() async {
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let resumeNow = lifecycle.withLock { state -> Bool in
          if case .stopped = state.phase {
            return true
          }
          state.completionAwaiters.append(continuation)
          return false
        }
        if resumeNow {
          continuation.resume()
        }
      }
    } onCancel: {
      Task { [weak self] in try? await self?.stopStreaming() }
    }
  }

  /// Attaches the consumer frames go to. Throws if one is already attached.
  func attach(_ consumer: any DataConsumer) throws {
    try lifecycle.withLock { state in
      guard case .idle = state.phase else {
        throw DeviceVideoStreamError.consumerAlreadyAttached
      }
      state.phase = .starting(awaiters: [])
    }
    self.consumer = consumer
  }

  /// One captured sample, on `writeQueue`: the first one moves the stream to `streaming` and
  /// resumes whoever awaited the start; every one is framed for the consumer unless it is behind.
  private func deliver(_ sampleBuffer: CMSampleBuffer) {
    guard let consumer, consumer.hasCapacityForFrame(logger: logger) else {
      return
    }
    let startAwaiters = lifecycle.withLock { state -> [CheckedContinuation<Void, Never>] in
      guard case let .starting(awaiters) = state.phase else {
        return []
      }
      state.phase = .streaming
      return awaiters
    }
    for awaiter in startAwaiters {
      awaiter.resume()
    }
    consumeSampleBuffer(sampleBuffer)
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
}

// MARK: - CaptureRelay

/// The one `NSObject` in the device video path: `AVCaptureVideoDataOutput` wants an Objective-C
/// delegate, so this forwards its two callbacks to closures.
private final class CaptureRelay: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  private let onSample: (CMSampleBuffer) -> Void
  private let onDrop: () -> Void

  init(onSample: @escaping (CMSampleBuffer) -> Void, onDrop: @escaping () -> Void) {
    self.onSample = onSample
    self.onDrop = onDrop
  }

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    onSample(sampleBuffer)
  }

  func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    onDrop()
  }
}

/// The sample format an `AVCaptureVideoDataOutput` is asked to deliver. The device encodes JPEG and
/// H.264 itself; everything else is BGRA pixels.
enum DeviceCaptureFormat {
  case bgra
  case jpeg
  /// The device's H.264 encoder output, as delivered.
  case h264

  /// What the capture output is asked for to stream `format`, or nil for a format the device cannot
  /// produce: it encodes H.264 only.
  init?(_ format: VideoStreamFormat) {
    switch format {
    case .compressedVideo(withCodec: .h264, transport: _):
      self = .h264
    case .compressedVideo(withCodec: .hevc, transport: _):
      return nil
    case .mjpeg, .minicap:
      self = .jpeg
    case .bgra:
      self = .bgra
    }
  }

  enum ConfigurationError: Error, LocalizedError {
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

  /// Sets the output's `videoSettings` for this format. Throws if the output cannot produce it.
  func configure(_ output: AVCaptureVideoDataOutput) throws {
    switch self {
    case .bgra:
      guard output.availableVideoPixelFormatTypes.contains(kCVPixelFormatType_32BGRA) else {
        throw ConfigurationError.unsupportedBGRAOutput
      }
      output.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
      ]
    case .jpeg:
      guard output.availableVideoCodecTypes.contains(.jpeg) else {
        throw ConfigurationError.unsupportedJPEGCodec
      }
      output.videoSettings = [
        AVVideoCodecKey: AVVideoCodecType.jpeg.rawValue,
        AVVideoCompressionPropertiesKey: [
          AVVideoQualityKey: 0.2
        ],
      ]
    case .h264:
      output.videoSettings = [:]
    }
  }
}
