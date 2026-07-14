/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The video codec for compressed video streams.
public enum FBVideoStreamCodec: String {
  case h264
  case hevc
}

/// The transport/container framing for compressed video streams.
public enum FBVideoStreamTransport: String {
  case annexB = "annex-b"
  case mpegts
  case fmp4
}

/// The format of a video stream: a compressed codec carried over a transport, or one of the raw/JPEG
/// formats that have no codec or transport. Modeled as a sum so `transport` exists only where it is
/// meaningful (the `compressedVideo` case) and every dispatch site matches exhaustively.
public enum FBVideoStreamFormat: Hashable {
  case compressedVideo(withCodec: FBVideoStreamCodec, transport: FBVideoStreamTransport)
  case mjpeg
  case minicap
  case bgra
}

extension FBVideoStreamFormat: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .compressedVideo(codec, transport):
      return "\(codec.rawValue) over \(transport.rawValue)"
    case .mjpeg:
      return "MJPEG"
    case .minicap:
      return "Minicap"
    case .bgra:
      return "BGRA"
    }
  }
}

/// The rate-control strategy for VTCompression: a target quality (0–1) or an average bitrate (in bits
/// per second). Modeled as a sum so quality stays a `Double` and bitrate an `Int` — the encoder wants
/// each as the corresponding CoreFoundation number type.
public enum FBVideoStreamRateControl: Hashable {
  case quality(Double)
  case bitrate(Int)
}

extension FBVideoStreamRateControl: CustomStringConvertible {
  public var description: String {
    switch self {
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

/// How frames are encoded, independent of the output format/sink: frame rate, scale, rate control, and
/// key-frame interval. Composed into `FBVideoStreamConfiguration` so the streaming and recording paths
/// can build and pass the same encode options, varying only the format (and, for record, the sink).
public struct FBVideoEncodeOptions {
  public let framesPerSecond: Int?
  public let scaleFactor: Double?
  public let rateControl: FBVideoStreamRateControl
  public let keyFrameRate: Double

  public init(framesPerSecond: Int?, rateControl: FBVideoStreamRateControl?, scaleFactor: Double?, keyFrameRate: Double?) {
    self.framesPerSecond = framesPerSecond
    self.rateControl = rateControl ?? .quality(0.75)
    self.scaleFactor = scaleFactor
    self.keyFrameRate = keyFrameRate ?? 1.0
  }
}

public final class FBVideoStreamConfiguration: NSObject, NSCopying {

  public let format: FBVideoStreamFormat
  public let encodeOptions: FBVideoEncodeOptions

  public var framesPerSecond: Int? { encodeOptions.framesPerSecond }
  public var rateControl: FBVideoStreamRateControl { encodeOptions.rateControl }
  public var scaleFactor: Double? { encodeOptions.scaleFactor }
  public var keyFrameRate: Double { encodeOptions.keyFrameRate }

  public init(format: FBVideoStreamFormat, encodeOptions: FBVideoEncodeOptions) {
    self.format = format
    self.encodeOptions = encodeOptions
    super.init()
  }

  public convenience init(format: FBVideoStreamFormat, framesPerSecond: Int?, rateControl: FBVideoStreamRateControl?, scaleFactor: Double?, keyFrameRate: Double?) {
    self.init(format: format, encodeOptions: FBVideoEncodeOptions(framesPerSecond: framesPerSecond, rateControl: rateControl, scaleFactor: scaleFactor, keyFrameRate: keyFrameRate))
  }

  // MARK: NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    self
  }

  // MARK: NSObject

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBVideoStreamConfiguration else { return false }
    return format == other.format
      && framesPerSecond == other.framesPerSecond
      && rateControl == other.rateControl
      && scaleFactor == other.scaleFactor
      && keyFrameRate == other.keyFrameRate
  }

  public override var hash: Int {
    var hasher = Hasher()
    hasher.combine(format)
    hasher.combine(framesPerSecond)
    hasher.combine(rateControl)
    hasher.combine(scaleFactor)
    hasher.combine(keyFrameRate)
    return hasher.finalize()
  }

  public override var description: String {
    "Format \(format) | FPS \(framesPerSecond.map { "\($0)" } ?? "nil") | Rate Control \(rateControl) | Scale \(scaleFactor.map { "\($0)" } ?? "nil") | Key frame rate \(keyFrameRate)"
  }
}
