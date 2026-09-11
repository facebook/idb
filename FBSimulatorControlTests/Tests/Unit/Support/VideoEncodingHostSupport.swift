/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import CoreVideo
import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

/// Probe for host hardware video encoding, memoized per process.
///
/// Several video tests drive a real VideoToolbox encode and wait on its output. Some hosts never
/// produce any: virtualized Macs with no hardware encoder, and virtualized Macs (GitHub-hosted
/// runners among them) whose VideoToolbox lists a hardware H.264 encoder that never emits a frame.
/// The encoder list cannot tell the second kind from a working host, so the probe runs the
/// production H.264 pipeline once, over a single frame, and reports whether a sample came out.
/// Capability-gated, not runner-gated: any host that can encode runs the tests, wherever it lives.
enum VideoEncodingHostSupport {
  enum HardwareH264Encoding {
    case available
    /// `reason` names the stage that gave up, so a skip caused by a broken probe reads differently
    /// from one caused by a host that genuinely cannot encode.
    case unavailable(reason: String)
  }

  static let hardwareH264Encoding: HardwareH264Encoding = probeHardwareH264Encoding()

  /// A working encoder returns its first sample within milliseconds. A host that will never emit
  /// pays this once per process, instead of a 10s timeout in every gated test.
  private static let probeTimeout: TimeInterval = 5

  /// Skips the calling test unless the host can hardware-encode H.264, naming why in the skip.
  static func skipUnlessHardwareH264Encoding() throws {
    if case .unavailable(let reason) = hardwareH264Encoding {
      throw XCTSkip("video encoding needs a working hardware H.264 encoder, unavailable on this host: \(reason)")
    }
  }

  private static func probeHardwareH264Encoding() -> HardwareH264Encoding {
    let pixelBuffer: CVPixelBuffer
    switch makeProbePixelBuffer() {
    case .success(let buffer):
      pixelBuffer = buffer
    case .failure(let status):
      return .unavailable(reason: "CVPixelBufferCreate failed with \(status)")
    }
    let firstSample = DispatchSemaphore(value: 0)
    let consumer = FBBlockDataConsumer.synchronousDataConsumer { _ in firstSample.signal() }
    let configuration = FBVideoStreamConfiguration(
      format: .compressedVideo(withCodec: .h264, transport: .annexB),
      framesPerSecond: nil,
      rateControl: nil,
      scaleFactor: nil,
      keyFrameRate: nil)
    let logger = CapturingLogger()

    let pusher: any SimulatorVideoStreamFramePusher
    do {
      pusher = try FBSimulatorVideoStream.framePusher(
        configuration: configuration,
        compressionSessionProperties: [:],
        consumer: consumer,
        encodedSampleConsumerOverride: nil,
        logger: logger)
      try pusher.setup(with: pixelBuffer, edgeInsets: FBVideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0))
      try pusher.writeEncodedFrame(
        pixelBuffer,
        frameNumber: 0,
        timeAtFirstFrame: CFAbsoluteTimeGetCurrent(),
        frameDuration: 0,
        forceKeyFrame: true)
    } catch {
      return .unavailable(reason: "encode pipeline setup threw \(error)\(pipelineLog(logger))")
    }
    let produced = firstSample.wait(timeout: .now() + probeTimeout) == .success
    try? pusher.tearDown()
    if produced {
      return .available
    }
    return .unavailable(reason: "no encoded sample within \(probeTimeout)s\(pipelineLog(logger))")
  }

  /// The pusher reports encode errors and drops only through its logger, so they are the best
  /// explanation of a probe that produced nothing.
  private static func pipelineLog(_ logger: CapturingLogger) -> String {
    let messages = logger.messages.compactMap { $0 as? String }
    if messages.isEmpty {
      return ""
    }
    return "; pipeline log: " + messages.joined(separator: " | ")
  }

  /// An IOSurface-backed BGRA frame, the same shape the stream mounts from the simulator's surface.
  private static func makeProbePixelBuffer() -> Result<CVPixelBuffer, CVReturnError> {
    let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(nil, 128, 128, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer)
    guard status == kCVReturnSuccess, let pixelBuffer else {
      return .failure(CVReturnError(status: status))
    }
    return .success(pixelBuffer)
  }

  private struct CVReturnError: Error, CustomStringConvertible {
    let status: CVReturn
    var description: String { "CVReturn \(status)" }
  }
}
