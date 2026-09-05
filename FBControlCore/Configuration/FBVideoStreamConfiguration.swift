/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The video codec for compressed video streams.
public enum FBVideoStreamCodec: String, Sendable {
  case h264
  case hevc
}

/// The transport/container framing for compressed video streams.
public enum FBVideoStreamTransport: String, Sendable {
  case annexB = "annex-b"
  case mpegts
  case fmp4
}

/// The encoders an MJPEG stream may use. Hardware encoding is required by default; software
/// encoding is a deliberate opt-in for hosts without a usable hardware JPEG encoder, trading CPU
/// for availability.
public enum FBMJPEGEncoderSelection: Hashable, Sendable {
  case requireHardware
  case allowSoftware
}

/// The format of a video stream: a compressed codec over a transport, or a raw/JPEG format that has neither.
public enum FBVideoStreamFormat: Hashable, Sendable {
  case compressedVideo(withCodec: FBVideoStreamCodec, transport: FBVideoStreamTransport)
  case mjpeg(encoder: FBMJPEGEncoderSelection)
  case minicap
  case bgra
}

extension FBVideoStreamFormat: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .compressedVideo(codec, transport):
      return "\(codec.rawValue) over \(transport.rawValue)"
    case .mjpeg(encoder: .requireHardware):
      return "MJPEG"
    case .mjpeg(encoder: .allowSoftware):
      return "MJPEG (software encoder permitted)"
    case .minicap:
      return "Minicap"
    case .bgra:
      return "BGRA"
    }
  }
}

/// The rate-control strategy for VTCompression: derived automatically, a target quality (0–1), or an
/// average bitrate in bits per second.
public enum FBVideoStreamRateControl: Hashable, Sendable {
  /// The default: derive a rate from what is being encoded. JPEG formats (MJPEG/Minicap) use their
  /// quality knob; H.264/HEVC derive an average bitrate from the encoded output dimensions at
  /// session setup. An explicit `quality` is NOT a substitute for H.264/HEVC — the low-latency
  /// hardware encoder accepts the Quality property but ignores it, falling back to its internal
  /// default bitrate (~2 Mbps regardless of resolution), which macroblocks badly under motion.
  case automatic
  /// A constant target quality (0–1). Honored by the JPEG formats; ignored by the low-latency
  /// hardware H.264/HEVC encoder (see `automatic`).
  case quality(Double)
  case bitrate(Int)
}

extension FBVideoStreamRateControl: CustomStringConvertible {
  public var description: String {
    switch self {
    case .automatic:
      return "Automatic"
    case let .quality(quality):
      return "Quality \(quality)"
    case let .bitrate(bitrate):
      let bps = Double(bitrate)
      if bps >= 1_000_000.0 {
        return String(format: "Bitrate %.1f Mbps", bps / 1_000_000.0)
      } else {
        return String(format: "Bitrate %.0f kbps", bps / 1000.0)
      }
    }
  }
}

/// How frames are encoded, independent of the output format and sink.
public struct FBVideoEncodeOptions: Hashable, Sendable {
  public let framesPerSecond: Int?
  public let scaleFactor: Double?
  public let rateControl: FBVideoStreamRateControl
  public let keyFrameRate: Double

  public init(framesPerSecond: Int?, rateControl: FBVideoStreamRateControl?, scaleFactor: Double?, keyFrameRate: Double?) {
    self.framesPerSecond = framesPerSecond
    self.rateControl = rateControl ?? .automatic
    self.scaleFactor = scaleFactor
    // Four seconds between forced keyframes: at retina sizes each IDR costs tens of kilobytes and resets
    // temporal prediction. Late joiners wait at most this long for a sync point; WebRTC re-syncs via
    // requestKeyFrame.
    self.keyFrameRate = keyFrameRate ?? 4.0
  }
}

/// Describes a video stream: the output format and the options controlling how frames are encoded.
public struct FBVideoStreamConfiguration: Hashable, CustomStringConvertible, Sendable {

  public let format: FBVideoStreamFormat
  public let encodeOptions: FBVideoEncodeOptions

  public var framesPerSecond: Int? { encodeOptions.framesPerSecond }
  public var rateControl: FBVideoStreamRateControl { encodeOptions.rateControl }
  public var scaleFactor: Double? { encodeOptions.scaleFactor }
  public var keyFrameRate: Double { encodeOptions.keyFrameRate }

  public init(format: FBVideoStreamFormat, encodeOptions: FBVideoEncodeOptions) {
    self.format = format
    self.encodeOptions = encodeOptions
  }

  public init(format: FBVideoStreamFormat, framesPerSecond: Int?, rateControl: FBVideoStreamRateControl?, scaleFactor: Double?, keyFrameRate: Double?) {
    self.init(format: format, encodeOptions: FBVideoEncodeOptions(framesPerSecond: framesPerSecond, rateControl: rateControl, scaleFactor: scaleFactor, keyFrameRate: keyFrameRate))
  }

  public var description: String {
    "Format \(format) | FPS \(framesPerSecond.map { "\($0)" } ?? "nil") | Rate Control \(rateControl) | Scale \(scaleFactor.map { "\($0)" } ?? "nil") | Key frame rate \(keyFrameRate)"
  }
}
