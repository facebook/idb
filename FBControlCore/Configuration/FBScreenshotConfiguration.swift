/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import Foundation

/// The container a screenshot is encoded into.
public enum FBScreenshotImageFormat: String, Hashable, Sendable, CaseIterable {
  case png
  case jpeg
  case tiff
}

/// How a screenshot is encoded. Modeled as a sum so a compression quality exists only on the format
/// that has one: a quality on PNG or TIFF is not a no-op to be ignored downstream, it is a request
/// that cannot be honored, and it is rejected where a request is decoded rather than carried inward.
public enum FBScreenshotEncoding: Hashable, Sendable {
  case png
  /// Uncompressed: preserves the pixels and color space with no codec cost.
  case tiff
  /// `quality` is in (0, 1].
  case jpeg(quality: Double)

  /// Used when a caller asks for JPEG without naming a quality. Matches the default the video
  /// stream encoder applies for the same reason.
  public static let defaultJPEGQuality: Double = 0.8

  public var format: FBScreenshotImageFormat {
    switch self {
    case .png:
      return .png
    case .tiff:
      return .tiff
    case .jpeg:
      return .jpeg
    }
  }

  /// The quality to hand the encoder, or `nil` for formats that have none.
  public var compressionQuality: Double? {
    switch self {
    case .png, .tiff:
      return nil
    case let .jpeg(quality):
      return quality
    }
  }
}

// MARK: - FBScreenshotEncoding: CustomStringConvertible

extension FBScreenshotEncoding: CustomStringConvertible {
  public var description: String {
    switch self {
    case .png:
      return "PNG"
    case .tiff:
      return "TIFF"
    case let .jpeg(quality):
      return String(format: "JPEG (quality %.2f)", quality)
    }
  }
}

/// The unit a crop rect or fit bound is expressed in. Points are the coordinate space that tap,
/// swipe and describe already use; pixels are what the framebuffer is actually in. The two differ by
/// the target's screen scale, which only the companion knows -- so a caller can work in the units it
/// already has rather than making a round trip to find out.
///
/// Not every target knows its own screen scale, so `points` is not universally available while
/// `pixels`, the default, always is. A request in points against a target that cannot resolve them
/// fails rather than guessing a scale of 1, which would silently return the wrong region.
public enum FBScreenshotUnit: String, Hashable, Sendable {
  case pixels
  case points
}

/// How much to shrink a screenshot. Never enlarges it: a caller asking to fit a 414-wide box is
/// asking for an upper bound, not a resample target, and upscaling would cost bytes to add no
/// detail.
public enum FBScreenshotScale: Hashable, Sendable {
  /// Capture at the target's native resolution.
  case native
  /// Multiply both dimensions by a factor in (0, 1].
  case factor(Double)
  /// Shrink to fit inside a bounding box. `nil` leaves that axis unbounded; at least one bound must
  /// be present. When both are given the more restrictive wins.
  ///
  /// One factor is applied to both axes, so the aspect ratio is preserved up to rounding: each side
  /// is rounded to a whole pixel independently, which on small images can move the ratio by a few
  /// percent. There is no way to avoid that and still return whole pixels.
  case fit(maxWidth: Int?, maxHeight: Int?)
}

// MARK: - FBScreenshotScale: CustomStringConvertible

extension FBScreenshotScale: CustomStringConvertible {
  public var description: String {
    switch self {
    case .native:
      return "Native"
    case let .factor(factor):
      return String(format: "Factor %.4f", factor)
    case let .fit(maxWidth, maxHeight):
      let width = maxWidth.map(String.init) ?? "unbounded"
      let height = maxHeight.map(String.init) ?? "unbounded"
      return "Fit \(width)x\(height)"
    }
  }
}

/// Describes a screenshot: what to capture, how much of it, at what size, in what encoding.
///
/// The default value reproduces the behaviour of a screenshot taken with no options at all -- full
/// screen, native resolution, PNG -- so a caller that does not care gets exactly what it got before
/// any of this existed.
public struct FBScreenshotConfiguration: Hashable, Sendable {

  public let encoding: FBScreenshotEncoding
  /// The region to capture, in `unit`, with a top-left origin. `nil` captures the whole screen.
  public let cropRect: CGRect?
  public let scale: FBScreenshotScale
  /// The unit `cropRect` and `scale`'s fit bounds are expressed in.
  public let unit: FBScreenshotUnit

  public init(
    encoding: FBScreenshotEncoding = .png,
    cropRect: CGRect? = nil,
    scale: FBScreenshotScale = .native,
    unit: FBScreenshotUnit = .pixels
  ) {
    self.encoding = encoding
    self.cropRect = cropRect
    self.scale = scale
    self.unit = unit
  }

  /// Whether resolving this configuration needs the target's screen scale.
  ///
  /// `unit` describes the measurements the caller supplied, and a request can supply none: a full
  /// screen at native resolution, or shrunk by a dimensionless factor, has nothing to convert. Only
  /// a crop rect and a fit bound are in units, so only those make a `points` request depend on a
  /// screen scale the target may not report.
  public var requiresScreenScale: Bool {
    guard unit == .points else {
      return false
    }
    if cropRect != nil {
      return true
    }
    if case .fit = scale {
      return true
    }
    return false
  }
}

// MARK: - FBScreenshotConfiguration: CustomStringConvertible

extension FBScreenshotConfiguration: CustomStringConvertible {
  public var description: String {
    let crop = cropRect.map { "\($0)" } ?? "full screen"
    return "Encoding \(encoding) | Crop \(crop) | Scale \(scale) | Unit \(unit.rawValue)"
  }
}

/// A captured screenshot and the dimensions it was produced at. The source dimensions and screen
/// scale are reported alongside the image so a caller can tell what it asked for from what it got --
/// a crop that overhung the screen was clamped, and a fit bound rarely lands on an exact multiple.
public struct FBScreenshotResult: Hashable, Sendable {

  public let imageData: Data
  public let format: FBScreenshotImageFormat
  /// The dimensions of `imageData`, in pixels, after cropping and scaling.
  public let size: CGSize
  /// The dimensions of the native capture, in pixels, before cropping and scaling.
  public let sourceSize: CGSize
  /// Pixels per point, or `nil` on a target that does not report its screen scale.
  public let screenScale: Double?

  public init(imageData: Data, format: FBScreenshotImageFormat, size: CGSize, sourceSize: CGSize, screenScale: Double?) {
    self.imageData = imageData
    self.format = format
    self.size = size
    self.sourceSize = sourceSize
    self.screenScale = screenScale
  }
}

/// The ways a screenshot request can be geometrically impossible, as data rather than assembled
/// strings. Each maps to an invalid-argument failure at the API boundary.
public enum FBScreenshotGeometryError: Error, Hashable {
  case scaleFactorOutOfRange(Double)
  case fitBoundsEmpty
  case fitBoundNotPositive(Int)
  case cropExtentNotPositive(CGRect)
  case cropOutsideBounds(cropRect: CGRect, sourceSize: CGSize)
  case sourceSizeNotPositive(CGSize)
  case screenScaleUnknown
}

// MARK: - FBScreenshotGeometryError: LocalizedError

extension FBScreenshotGeometryError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .scaleFactorOutOfRange(factor):
      return "Scale factor \(factor) is not in the range (0, 1]; a screenshot can be shrunk but not enlarged"
    case .fitBoundsEmpty:
      return "A fit needs at least one of a maximum width or a maximum height"
    case let .fitBoundNotPositive(bound):
      return "Fit bound \(bound) is not positive"
    case let .cropExtentNotPositive(cropRect):
      return "Crop rect \(cropRect) has a non-positive width or height"
    case let .cropOutsideBounds(cropRect, sourceSize):
      return "Crop rect \(cropRect) lies entirely outside a screen of \(Int(sourceSize.width))x\(Int(sourceSize.height)) pixels"
    case let .sourceSizeNotPositive(sourceSize):
      return "Captured image of \(sourceSize) has a non-positive width or height"
    case .screenScaleUnknown:
      return "This target does not report a screen scale, so a screenshot region cannot be given in points; use pixels"
    }
  }
}

/// The transform to apply to a captured image, resolved against the dimensions it was actually
/// captured at: everything is in pixels and every bound has been checked.
///
/// Producing this is separated from performing it so the arithmetic -- unit conversion, clamping,
/// aspect-preserving fit, rounding -- is testable without a simulator, and so the simulator and
/// device paths cannot disagree about what a given request means.
public struct FBScreenshotPlan: Hashable, Sendable {

  /// The region to capture, in pixels, clamped to the source and rounded out to whole pixels.
  /// `nil` captures the whole source image.
  public let cropRect: CGRect?
  /// In (0, 1]. Exactly 1 means no resampling is needed.
  public let scaleFactor: Double
  /// The final dimensions in pixels. Always at least 1x1.
  public let outputSize: CGSize

  public init(cropRect: CGRect?, scaleFactor: Double, outputSize: CGSize) {
    self.cropRect = cropRect
    self.scaleFactor = scaleFactor
    self.outputSize = outputSize
  }

  /// True when the image can be encoded exactly as captured.
  public var isIdentity: Bool {
    cropRect == nil && scaleFactor == 1
  }
}

/// The screenshot geometry, as pure functions over sizes.
public enum FBScreenshotGeometry {

  /// Resolves `configuration` against the dimensions an image was captured at.
  ///
  /// Crop is applied before scale, so a caller cropping to a small region and bounding the result
  /// gets the region shrunk to that bound, and the scaler never touches pixels that are about to be
  /// discarded.
  ///
  /// - Parameters:
  ///   - sourceSize: the native capture size, in pixels.
  ///   - screenScale: pixels per point, or `nil` on a target that does not report one. Only needed
  ///     to convert a measurement the caller gave in points, so a `nil` scale is an error only for
  ///     a request that carries one -- a request in pixels, and a request in points that measures
  ///     nothing, work on any target.
  public static func plan(
    for configuration: FBScreenshotConfiguration,
    sourceSize: CGSize,
    screenScale: Double?
  ) throws -> FBScreenshotPlan {
    guard sourceSize.width >= 1, sourceSize.height >= 1 else {
      throw FBScreenshotGeometryError.sourceSizeNotPositive(sourceSize)
    }
    // Resolved lazily: a full-screen native capture in points converts nothing, and failing it for
    // want of a scale it never needed would deny a caller an image it could have had.
    let scale =
      try configuration.requiresScreenScale
      ? pointsToPixels(for: configuration.unit, screenScale: screenScale)
      : 1

    let cropRect = try configuration.cropRect.map {
      try clampedCropRect($0, pointsToPixels: scale, sourceSize: sourceSize)
    }
    let baseSize = cropRect?.size ?? sourceSize
    let factor = try scaleFactor(for: configuration.scale, baseSize: baseSize, pointsToPixels: scale)

    return FBScreenshotPlan(
      cropRect: cropRect,
      scaleFactor: factor,
      outputSize: outputSize(baseSize: baseSize, factor: factor)
    )
  }

  /// The multiplier that takes a measurement in `unit` to pixels.
  static func pointsToPixels(for unit: FBScreenshotUnit, screenScale: Double?) throws -> Double {
    switch unit {
    case .pixels:
      return 1
    case .points:
      // Falling back to 1 here would answer a request for a region with a different region, at a
      // third of the size on a 3x screen, and report success.
      guard let screenScale, screenScale > 0 else {
        throw FBScreenshotGeometryError.screenScaleUnknown
      }
      return screenScale
    }
  }

  /// Converts a crop rect into whole pixels and clamps it to the source.
  ///
  /// A rect that overhangs the screen is clamped rather than rejected -- a caller cropping around a
  /// element near the edge should get the part that exists -- but one that misses the screen
  /// entirely is an error, because there is no sensible image to return.
  static func clampedCropRect(_ cropRect: CGRect, pointsToPixels: Double, sourceSize: CGSize) throws -> CGRect {
    // Read the extent off `size` rather than `width`/`height`, which are standardized: a rect with a
    // negative height reports a positive one, so this guard would pass and the rect would silently
    // become one extending upward from the requested origin.
    guard cropRect.size.width > 0, cropRect.size.height > 0 else {
      throw FBScreenshotGeometryError.cropExtentNotPositive(cropRect)
    }
    let pixelRect = CGRect(
      x: cropRect.origin.x * pointsToPixels,
      y: cropRect.origin.y * pointsToPixels,
      width: cropRect.size.width * pointsToPixels,
      height: cropRect.size.height * pointsToPixels
    ).integral
    let bounds = CGRect(origin: .zero, size: sourceSize)
    let clamped = pixelRect.intersection(bounds)
    guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else {
      throw FBScreenshotGeometryError.cropOutsideBounds(cropRect: cropRect, sourceSize: sourceSize)
    }
    return clamped
  }

  /// The factor that shrinks `baseSize` as `scale` asks, in (0, 1].
  static func scaleFactor(for scale: FBScreenshotScale, baseSize: CGSize, pointsToPixels: Double) throws -> Double {
    switch scale {
    case .native:
      return 1
    case let .factor(factor):
      guard factor > 0, factor <= 1 else {
        throw FBScreenshotGeometryError.scaleFactorOutOfRange(factor)
      }
      return factor
    case let .fit(maxWidth, maxHeight):
      if maxWidth == nil, maxHeight == nil {
        throw FBScreenshotGeometryError.fitBoundsEmpty
      }
      var factor = 1.0
      for (bound, extent) in [(maxWidth, baseSize.width), (maxHeight, baseSize.height)] {
        guard let bound else {
          continue
        }
        guard bound > 0 else {
          throw FBScreenshotGeometryError.fitBoundNotPositive(bound)
        }
        // The more restrictive bound wins, and neither one enlarges.
        factor = min(factor, Double(bound) * pointsToPixels / Double(extent))
      }
      return factor
    }
  }

  /// The pixel dimensions `baseSize` scaled by `factor` rounds to.
  ///
  /// Rounds half up rather than to even, matching what the common image libraries do, so a caller
  /// migrating from a client-side resize gets the same dimensions. Floors at one pixel per side: a
  /// zero-dimension image is not a smaller image, it is a broken one.
  ///
  /// Each axis rounds on its own, so the output aspect ratio is the input's only to within half a
  /// pixel per side. That is a few percent on a very small image and imperceptible on a large one.
  /// Rounding the pair together would keep the ratio exact at the cost of missing the bound the
  /// caller asked to fit inside, which is the worse trade.
  static func outputSize(baseSize: CGSize, factor: Double) -> CGSize {
    CGSize(
      width: roundToPixels(Double(baseSize.width) * factor),
      height: roundToPixels(Double(baseSize.height) * factor)
    )
  }

  static func roundToPixels(_ value: Double) -> Double {
    max(1, (value + 0.5).rounded(.down))
  }
}
