/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import CoreVideo
import Foundation

/// The sample format an `AVCaptureVideoDataOutput` is asked to deliver. The device encodes JPEG and
/// H.264 itself; everything else is BGRA pixels.
enum DeviceCaptureFormat {
  case bgra
  case jpeg
  /// The device's H.264 encoder output, as delivered.
  case h264

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
