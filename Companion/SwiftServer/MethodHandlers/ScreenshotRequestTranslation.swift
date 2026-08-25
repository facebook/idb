/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import Foundation
import GRPC
import IDBGRPCSwift

/// The pure translation between a `screenshot` request and the framework's configuration type, and
/// between a capture and the response. Free of the command executor so the wire contract is pinned
/// by unit tests without a target; the method handler stays a thin dispatcher.
///
/// The proto can express request shapes the configuration type cannot -- a compression quality on a
/// lossless format, an unrecognized enum value -- because protobuf has no sum types. Rejecting those
/// here is what lets the framework take a configuration that is correct by construction.
enum ScreenshotRequestTranslation {

  // MARK: - Request

  static func configuration(from request: Idb_ScreenshotRequest) throws -> FBScreenshotConfiguration {
    FBScreenshotConfiguration(
      encoding: try encoding(from: request),
      cropRect: cropRect(from: request),
      scale: scale(from: request),
      unit: try unit(from: request)
    )
  }

  private static func encoding(from request: Idb_ScreenshotRequest) throws -> FBScreenshotEncoding {
    switch request.format {
    case .png:
      try rejectCompressionQuality(on: request, format: "PNG")
      return .png
    case .tiff:
      try rejectCompressionQuality(on: request, format: "TIFF")
      return .tiff
    case .jpeg:
      // Unset is 0 on the wire and cannot be told apart from a deliberate 0, which is not a legal
      // quality anyway. Both mean "whatever the server thinks is reasonable".
      guard request.compressionQuality != 0 else {
        return .jpeg(quality: FBScreenshotEncoding.defaultJPEGQuality)
      }
      guard request.compressionQuality > 0, request.compressionQuality <= 1 else {
        throw GRPCStatus(
          code: .invalidArgument,
          message: "compression_quality \(request.compressionQuality) is not in (0, 1]"
        )
      }
      return .jpeg(quality: request.compressionQuality)
    case let .UNRECOGNIZED(value):
      throw GRPCStatus(code: .invalidArgument, message: "\(value) is not a recognized screenshot format")
    }
  }

  /// A quality on a format that has none is an error rather than a no-op, so that a caller who
  /// believes they are getting a smaller image finds out that they are not.
  private static func rejectCompressionQuality(on request: Idb_ScreenshotRequest, format: String) throws {
    guard request.compressionQuality == 0 else {
      throw GRPCStatus(code: .invalidArgument, message: "compression_quality is not meaningful for \(format)")
    }
  }

  private static func cropRect(from request: Idb_ScreenshotRequest) -> CGRect? {
    guard request.hasCrop else {
      return nil
    }
    return CGRect(
      x: request.crop.x,
      y: request.crop.y,
      width: request.crop.width,
      height: request.crop.height
    )
  }

  private static func scale(from request: Idb_ScreenshotRequest) -> FBScreenshotScale {
    guard let scale = request.scale else {
      return .native
    }
    switch scale {
    case let .scaleFactor(factor):
      return .factor(factor)
    case let .fit(fit):
      // 0 is unset on the wire, and an unset bound means unbounded on that axis rather than a
      // bound of zero. Both being unset is rejected by the geometry, not treated as native, since
      // a caller who sent a `fit` at all meant to bound something.
      return .fit(
        maxWidth: fit.maxWidth == 0 ? nil : Int(fit.maxWidth),
        maxHeight: fit.maxHeight == 0 ? nil : Int(fit.maxHeight)
      )
    }
  }

  private static func unit(from request: Idb_ScreenshotRequest) throws -> FBScreenshotUnit {
    switch request.unit {
    case .pixels:
      return .pixels
    case .points:
      return .points
    case let .UNRECOGNIZED(value):
      throw GRPCStatus(code: .invalidArgument, message: "\(value) is not a recognized screenshot unit")
    }
  }

  // MARK: - Response

  static func response(from result: FBScreenshotResult) -> Idb_ScreenshotResponse {
    .with {
      $0.imageData = result.imageData
      $0.imageFormat = result.format.rawValue
      // The proto names these for their role in the capture; the framework names them for what
      // they measure. This is the seam that maps one onto the other.
      $0.destination = size(result.size)
      $0.source = size(result.sourceSize)
      // 0 is the documented "this target does not report one" value. A real scale is never 0, so it
      // needs no separate presence bit.
      $0.screenScale = result.screenScale ?? 0
    }
  }

  private static func size(_ value: CGSize) -> Idb_ScreenshotResponse.Size {
    .with {
      $0.width = pixels(value.width)
      $0.height = pixels(value.height)
    }
  }

  /// A measurement is reported as a best effort, so a value the wire cannot carry is reported as
  /// "not reported" rather than taken down with the response. `UInt32(_: CGFloat)` traps on a
  /// negative, non-finite or too-large value, and a dimension arriving here wrong is a bug in the
  /// render -- but killing the companion process over a metadata field, after the image itself came
  /// back fine, is a worse answer than an absent number.
  private static func pixels(_ value: CGFloat) -> UInt32 {
    guard value.isFinite, value > 0 else {
      return 0
    }
    return UInt32(min(value.rounded(), CGFloat(UInt32.max)))
  }

  // MARK: - Errors

  /// Maps a geometry rejection onto a status code. The geometry is the single place these rules
  /// live -- restating them here would be a second copy to drift -- so the request reaches it
  /// intact and its refusal is translated on the way back out.
  static func status(for error: FBScreenshotGeometryError) -> GRPCStatus {
    switch error {
    case .scaleFactorOutOfRange, .fitBoundsEmpty, .fitBoundNotPositive,
      .cropExtentNotPositive, .cropOutsideBounds:
      return GRPCStatus(code: .invalidArgument, message: error.localizedDescription)
    case .screenScaleUnknown:
      // The request is well formed, and the same request succeeds against a target that reports a
      // screen scale. That is target state rather than a bad argument.
      return GRPCStatus(code: .failedPrecondition, message: error.localizedDescription)
    case .sourceSizeNotPositive:
      // The target handed back an empty screen. Nothing the caller sent could cause this.
      return GRPCStatus(code: .internalError, message: error.localizedDescription)
    }
  }

  /// Maps a render failure onto a status code.
  ///
  /// Without this a failed crop, an unencodable image or unreadable capture bytes reach the caller
  /// as an `UNKNOWN` with no message, which says only that the screenshot did not happen. These are
  /// the target's or the encoder's failure rather than the request's, so they are internal -- but a
  /// caller retrying, or a report of one, is worth more with the reason attached.
  static func status(for error: FBScreenshotRenderError) -> GRPCStatus {
    switch error {
    case .croppingFailed, .contextCreationFailed, .scalingFailed, .destinationCreationFailed,
      .encodingFailed, .unreadableImageData, .unknownImageDimensions, .decodingFailed:
      return GRPCStatus(code: .internalError, message: error.localizedDescription)
    case .compressionQualityOutOfRange:
      // Rejected on the way in, so reaching here means the request was not the one translated. Kept
      // as an invalid argument anyway, because that is what it describes.
      return GRPCStatus(code: .invalidArgument, message: error.localizedDescription)
    }
  }
}
