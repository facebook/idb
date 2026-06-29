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

/// The rate-control mode for VTCompression.
public enum FBVideoStreamRateControlMode: Int {
  case constantQuality
  case averageBitrate
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

@objc(FBVideoStreamRateControl)
public final class FBVideoStreamRateControl: NSObject, NSCopying {

  public let mode: FBVideoStreamRateControlMode
  @objc public let value: NSNumber

  @objc(quality:)
  public class func quality(_ quality: NSNumber) -> FBVideoStreamRateControl {
    FBVideoStreamRateControl(mode: .constantQuality, value: quality)
  }

  @objc(bitrate:)
  public class func bitrate(_ bitrate: NSNumber) -> FBVideoStreamRateControl {
    FBVideoStreamRateControl(mode: .averageBitrate, value: bitrate)
  }

  private init(mode: FBVideoStreamRateControlMode, value: NSNumber) {
    self.mode = mode
    self.value = value
    super.init()
  }

  // MARK: NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    self
  }

  // MARK: NSObject

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBVideoStreamRateControl else { return false }
    return mode == other.mode && value.isEqual(to: other.value)
  }

  public override var hash: Int {
    Int(mode.rawValue) ^ value.hash
  }

  public override var description: String {
    switch mode {
    case .constantQuality:
      return "Quality \(value)"
    case .averageBitrate:
      let bps = value.doubleValue
      if bps >= 1000000.0 {
        return String(format: "Bitrate %.1f Mbps", bps / 1000000.0)
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
  public let framesPerSecond: NSNumber?
  public let scaleFactor: NSNumber?
  public let rateControl: FBVideoStreamRateControl
  public let keyFrameRate: NSNumber

  public init(framesPerSecond: NSNumber?, rateControl: FBVideoStreamRateControl?, scaleFactor: NSNumber?, keyFrameRate: NSNumber?) {
    self.framesPerSecond = framesPerSecond
    self.rateControl = (rateControl?.copy() as? FBVideoStreamRateControl) ?? FBVideoStreamRateControl.quality(0.75)
    self.scaleFactor = scaleFactor
    self.keyFrameRate = keyFrameRate ?? 1.0
  }
}

@objc(FBVideoStreamConfiguration)
public final class FBVideoStreamConfiguration: NSObject, NSCopying {

  public let format: FBVideoStreamFormat
  public let encodeOptions: FBVideoEncodeOptions

  public var framesPerSecond: NSNumber? { encodeOptions.framesPerSecond }
  public var rateControl: FBVideoStreamRateControl { encodeOptions.rateControl }
  public var scaleFactor: NSNumber? { encodeOptions.scaleFactor }
  public var keyFrameRate: NSNumber { encodeOptions.keyFrameRate }

  public init(format: FBVideoStreamFormat, encodeOptions: FBVideoEncodeOptions) {
    self.format = format
    self.encodeOptions = encodeOptions
    super.init()
  }

  public convenience init(format: FBVideoStreamFormat, framesPerSecond: NSNumber?, rateControl: FBVideoStreamRateControl?, scaleFactor: NSNumber?, keyFrameRate: NSNumber?) {
    self.init(format: format, encodeOptions: FBVideoEncodeOptions(framesPerSecond: framesPerSecond, rateControl: rateControl, scaleFactor: scaleFactor, keyFrameRate: keyFrameRate))
  }

  // MARK: NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    self
  }

  // MARK: NSObject

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBVideoStreamConfiguration else { return false }
    if format != other.format { return false }
    let fpsEqual: Bool = framesPerSecond == other.framesPerSecond || (framesPerSecond != nil && other.framesPerSecond != nil && framesPerSecond!.isEqual(to: other.framesPerSecond!))
    if !fpsEqual { return false }
    if !rateControl.isEqual(other.rateControl) { return false }
    let scaleEqual: Bool = scaleFactor == other.scaleFactor || (scaleFactor != nil && other.scaleFactor != nil && scaleFactor!.isEqual(to: other.scaleFactor!))
    if !scaleEqual { return false }
    return keyFrameRate.isEqual(to: other.keyFrameRate)
  }

  public override var hash: Int {
    format.hashValue ^ (framesPerSecond?.hash ?? 0) ^ rateControl.hash ^ (scaleFactor?.hash ?? 0) ^ keyFrameRate.hash
  }

  public override var description: String {
    "Format \(format) | FPS \(framesPerSecond?.description ?? "nil") | Rate Control \(rateControl) | Scale \(scaleFactor?.description ?? "nil") | Key frame rate \(keyFrameRate)"
  }
}
