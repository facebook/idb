/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import VideoToolbox

/// Where encoded frames go, which decides the encoder's latency/quality trade-off.
public enum VideoEncodeSink: Sendable {
  /// A consumer displays frames as they arrive: low-latency rate control, no frame reordering and no
  /// encoder delay, so a frame is out within the frame interval.
  case live
  /// Frames are muxed to a file: the standard encoder, free to reorder (B-frames) and look ahead,
  /// which is quality-per-bit a viewer of the finished file gets for nothing.
  case file
}

/// Everything a `VTCompressionSession` is told, derived once from the stream configuration, the
/// cadence it runs at and the sink its output goes to. The encoder specification is fixed at
/// creation; the session properties depend on the encoded output size, which is only known once a
/// surface has mounted, so they are a function of it.
struct VideoToolboxEncoderSettings {
  let format: VideoStreamFormat
  let rateControl: VideoStreamRateControl
  /// Seconds between forced keyframes.
  let keyFrameInterval: Double
  let cadence: VideoStreamCadence
  let sink: VideoEncodeSink

  init(configuration: VideoStreamConfiguration, cadence: VideoStreamCadence, sink: VideoEncodeSink) {
    self.format = configuration.format
    self.rateControl = configuration.rateControl
    self.keyFrameInterval = configuration.keyFrameRate
    self.cadence = cadence
    self.sink = sink
  }

  /// The `kVTVideoEncoderSpecification_*` dictionary for `VTCompressionSessionCreate`.
  var encoderSpecification: [String: Any] {
    switch (format, sink) {
    case (.mjpeg(encoder: .allowSoftware), _):
      return [
        kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true
      ]
    case (.mjpeg(encoder: .requireHardware), _), (.minicap, _), (.bgra, _), (.compressedVideo, .file):
      return [
        kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true
      ]
    case (.compressedVideo, .live):
      // Low-latency rate control exists only on the H.264/HEVC encoders; a JPEG session refuses to
      // be created with it requested. A file sink wants the standard encoder's quality instead.
      return [
        kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true,
        kVTVideoEncoderSpecification_EnableLowLatencyRateControl as String: true,
      ]
    }
  }

  /// The `VTSessionSetProperties` dictionary for a session encoding `outputWidth`×`outputHeight`.
  func sessionProperties(outputWidth: Int, outputHeight: Int) -> [String: Any] {
    var properties: [String: Any] = [
      kVTCompressionPropertyKey_RealTime as String: true,
      kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration as String: keyFrameInterval,
    ]
    switch cadence {
    case .lazy:
      break
    case let .eager(framesPerSecond):
      properties[kVTCompressionPropertyKey_ExpectedFrameRate as String] = framesPerSecond
    }
    switch format {
    case let .compressedVideo(codec, _):
      // Frame reordering and encoder delay are H.264/HEVC concepts; a JPEG session ignores the keys.
      switch sink {
      case .live:
        properties[kVTCompressionPropertyKey_AllowFrameReordering as String] = false
        properties[kVTCompressionPropertyKey_MaxFrameDelayCount as String] = 0
      case .file:
        properties[kVTCompressionPropertyKey_AllowFrameReordering as String] = true
      }
      properties.merge(rateControlProperties(outputWidth: outputWidth, outputHeight: outputHeight)) { _, resolved in resolved }
      switch codec {
      case .h264:
        properties[kVTCompressionPropertyKey_ProfileLevel as String] = kVTProfileLevel_H264_High_AutoLevel as String
        properties[kVTCompressionPropertyKey_H264EntropyMode as String] = kVTH264EntropyMode_CABAC as String
      case .hevc:
        properties[kVTCompressionPropertyKey_AllowOpenGOP as String] = false
        properties[kVTCompressionPropertyKey_ProfileLevel as String] = kVTProfileLevel_HEVC_Main_AutoLevel as String
      }
    case .mjpeg, .minicap, .bgra:
      switch rateControl {
      case .automatic:
        // JPEG formats honor the quality knob (the value the pre-automatic default used).
        properties[kVTCompressionPropertyKey_Quality as String] = 0.75
      case let .bitrate(bitrate):
        properties[kVTCompressionPropertyKey_AverageBitRate as String] = bitrate
      case let .quality(quality):
        properties[kVTCompressionPropertyKey_Quality as String] = quality
      }
    }
    return properties
  }

  // MARK: - Compressed video rate control

  /// The `.automatic` rate-control budget: 4 bits per output pixel per second (≈0.08 bits/pixel per
  /// frame at a 50fps pan). Measured on the liquid-glass home screen: below ≈0.05 bpp the hardware
  /// encoder visibly macroblocks smooth gradients during full-screen motion, and it saturates around
  /// ≈14 Mbps at native retina size, so a larger budget buys little. Scales with `--scale`.
  static func automaticAverageBitRate(width: Int, height: Int) -> Int {
    width * height * 4
  }

  /// The quality at which `.quality` meets the `.automatic` budget; the budget scales linearly with
  /// quality either side of it, so 1.0 is a third more than automatic and 0.25 a third of it.
  static let automaticEquivalentQuality = 0.75

  /// The average bitrate a `.quality` rate control means for compressed video at this output size.
  static func averageBitRate(width: Int, height: Int, quality: Double) -> Int {
    let clamped = min(max(quality, 0.01), 1.0)
    return Int(Double(automaticAverageBitRate(width: width, height: height)) * clamped / automaticEquivalentQuality)
  }

  /// The rate-control properties for an H.264/HEVC session at its encoded output size. The
  /// low-latency hardware encoder accepts the `Quality` property but ignores it and, given no
  /// `AverageBitRate`, falls back to an internal default (~2 Mbps regardless of resolution) that
  /// macroblocks full-screen motion at retina sizes — so every strategy resolves to an average
  /// bitrate here. `DataRateLimits` bounds any one-second window to 1.5× that average: enough for a
  /// keyframe, not for the unbounded burst that stalls a pipe or socket consumer.
  func rateControlProperties(outputWidth: Int, outputHeight: Int) -> [String: Any] {
    let averageBitRate: Int
    switch rateControl {
    case .automatic:
      averageBitRate = Self.automaticAverageBitRate(width: outputWidth, height: outputHeight)
    case let .quality(quality):
      averageBitRate = Self.averageBitRate(width: outputWidth, height: outputHeight, quality: quality)
    case let .bitrate(bitrate):
      averageBitRate = bitrate
    }
    let burstBytesPerSecond = averageBitRate * 3 / 16
    return [
      kVTCompressionPropertyKey_AverageBitRate as String: averageBitRate,
      kVTCompressionPropertyKey_DataRateLimits as String: [burstBytesPerSecond, 1],
    ]
  }
}
