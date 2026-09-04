/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import IDBGRPCSwift

/// Translates a `video_stream` request to `FBVideoStreamConfiguration`. Zero is unset on the wire and
/// maps to nil so the framework substitutes its defaults.
enum VideoStreamRequestTranslation {

  static func configuration(from start: Idb_VideoStreamRequest.Start) -> FBVideoStreamConfiguration {
    let rateControl: FBVideoStreamRateControl?
    if start.avgBitrate > 0 {
      rateControl = .bitrate(Int(start.avgBitrate))
    } else if start.compressionQuality > 0 {
      rateControl = .quality(Double(start.compressionQuality))
    } else {
      rateControl = nil
    }

    return FBVideoStreamConfiguration(
      format: format(from: start.format),
      // Unset means the display's own rate, which is what a stream wants; a recording pins 30.
      framesPerSecond: start.fps > 0 ? Int(start.fps) : nil,
      rateControl: rateControl,
      scaleFactor: start.scaleFactor > 0 ? start.scaleFactor : nil,
      keyFrameRate: start.keyFrameRate > 0 ? start.keyFrameRate : nil)
  }

  static func format(from requestFormat: Idb_VideoStreamRequest.Format) -> FBVideoStreamFormat {
    switch requestFormat {
    case .h264:
      return .compressedVideo(withCodec: .h264, transport: .annexB)
    case .rbga:
      return .bgra
    case .mjpeg:
      return .mjpeg(encoder: .requireHardware)
    case .minicap:
      return .minicap
    case .i420, .UNRECOGNIZED:
      return .compressedVideo(withCodec: .h264, transport: .annexB)
    }
  }
}
