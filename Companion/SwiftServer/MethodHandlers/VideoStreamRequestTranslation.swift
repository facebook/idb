/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import IDBGRPCSwift

/// The pure translation between a `video_stream` request and the framework's stream configuration.
/// Free of the target and the sink so the wire contract is pinned by unit tests; the method handler
/// keeps the consumer wiring.
///
/// Every numeric field is a proto3 scalar, so zero is indistinguishable from unset. The framework
/// substitutes its defaults for nil and not for zero, so mapping zero to nil here is what makes an
/// unset field mean "the default" rather than the degenerate value zero names.
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
