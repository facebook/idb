/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBVideoStreamFormat)
public final class FBVideoStreamFormat: NSObject, NSCopying {

  @objc public let type: FBVideoStreamFormatType
  @objc public let codec: FBVideoStreamCodec?
  @objc public let transport: FBVideoStreamTransport?

  @objc(compressedVideoWithCodec:transport:)
  public class func compressedVideo(withCodec codec: FBVideoStreamCodec, transport: FBVideoStreamTransport) -> FBVideoStreamFormat {
    return FBVideoStreamFormat(type: .compressedVideo, codec: codec, transport: transport)
  }

  @objc
  public class func mjpeg() -> FBVideoStreamFormat {
    return FBVideoStreamFormat(type: .mjpeg, codec: nil, transport: nil)
  }

  @objc
  public class func minicap() -> FBVideoStreamFormat {
    return FBVideoStreamFormat(type: .minicap, codec: nil, transport: nil)
  }

  @objc
  public class func bgra() -> FBVideoStreamFormat {
    return FBVideoStreamFormat(type: .bgra, codec: nil, transport: nil)
  }

  private init(type: FBVideoStreamFormatType, codec: FBVideoStreamCodec?, transport: FBVideoStreamTransport?) {
    self.type = type
    self.codec = codec
    self.transport = transport
    super.init()
  }

  // MARK: NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    return self
  }

  // MARK: NSObject

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBVideoStreamFormat else { return false }
    if type != other.type { return false }
    if type == .compressedVideo {
      return codec == other.codec && transport == other.transport
    }
    return true
  }

  public override var hash: Int {
    var h = Int(type.rawValue)
    h ^= codec?.hashValue ?? 0
    h ^= transport?.hashValue ?? 0
    return h
  }

  public override var description: String {
    switch type {
    case .compressedVideo:
      return "\(codec?.rawValue ?? "") over \(transport?.rawValue ?? "")"
    case .mjpeg:
      return "MJPEG"
    case .minicap:
      return "Minicap"
    case .bgra:
      return "BGRA"
    @unknown default:
      return "Format(\(type.rawValue))"
    }
  }
}

@objc(FBVideoStreamRateControl)
public final class FBVideoStreamRateControl: NSObject, NSCopying {

  @objc public let mode: FBVideoStreamRateControlMode
  @objc public let value: NSNumber

  @objc(quality:)
  public class func quality(_ quality: NSNumber) -> FBVideoStreamRateControl {
    return FBVideoStreamRateControl(mode: .constantQuality, value: quality)
  }

  @objc(bitrate:)
  public class func bitrate(_ bitrate: NSNumber) -> FBVideoStreamRateControl {
    return FBVideoStreamRateControl(mode: .averageBitrate, value: bitrate)
  }

  private init(mode: FBVideoStreamRateControlMode, value: NSNumber) {
    self.mode = mode
    self.value = value
    super.init()
  }

  // MARK: NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    return self
  }

  // MARK: NSObject

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBVideoStreamRateControl else { return false }
    return mode == other.mode && value.isEqual(to: other.value)
  }

  public override var hash: Int {
    return Int(mode.rawValue) ^ value.hash
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
    @unknown default:
      return "RateControl(\(mode.rawValue), \(value))"
    }
  }
}

@objc(FBVideoStreamConfiguration)
public final class FBVideoStreamConfiguration: NSObject, NSCopying {

  @objc public let format: FBVideoStreamFormat
  @objc public let framesPerSecond: NSNumber?
  @objc public let rateControl: FBVideoStreamRateControl
  @objc public let scaleFactor: NSNumber?
  @objc public let keyFrameRate: NSNumber

  @objc
  public init(format: FBVideoStreamFormat, framesPerSecond: NSNumber?, rateControl: FBVideoStreamRateControl?, scaleFactor: NSNumber?, keyFrameRate: NSNumber?) {
    self.format = format.copy() as! FBVideoStreamFormat
    self.framesPerSecond = framesPerSecond
    self.rateControl = (rateControl?.copy() as? FBVideoStreamRateControl) ?? FBVideoStreamRateControl.quality(0.75)
    self.scaleFactor = scaleFactor
    self.keyFrameRate = keyFrameRate ?? 1.0
    super.init()
  }

  // MARK: NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    return self
  }

  // MARK: NSObject

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBVideoStreamConfiguration else { return false }
    if !format.isEqual(other.format) { return false }
    let fpsEqual: Bool = framesPerSecond == other.framesPerSecond || (framesPerSecond != nil && other.framesPerSecond != nil && framesPerSecond!.isEqual(to: other.framesPerSecond!))
    if !fpsEqual { return false }
    if !rateControl.isEqual(other.rateControl) { return false }
    let scaleEqual: Bool = scaleFactor == other.scaleFactor || (scaleFactor != nil && other.scaleFactor != nil && scaleFactor!.isEqual(to: other.scaleFactor!))
    if !scaleEqual { return false }
    return keyFrameRate.isEqual(to: other.keyFrameRate)
  }

  public override var hash: Int {
    return format.hash ^ (framesPerSecond?.hash ?? 0) ^ rateControl.hash ^ (scaleFactor?.hash ?? 0) ^ keyFrameRate.hash
  }

  public override var description: String {
    return "Format \(format) | FPS \(framesPerSecond?.description ?? "nil") | Rate Control \(rateControl) | Scale \(scaleFactor?.description ?? "nil") | Key frame rate \(keyFrameRate)"
  }
}
