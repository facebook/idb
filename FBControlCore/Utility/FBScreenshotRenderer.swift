/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The ways rendering a planned screenshot can fail, as data rather than assembled strings.
public enum FBScreenshotRenderError: Error, Hashable {
  case croppingFailed(cropRect: CGRect, sourceSize: CGSize)
  case contextCreationFailed(size: CGSize)
  case scalingFailed(size: CGSize)
  case destinationCreationFailed(format: FBScreenshotImageFormat)
  case encodingFailed(format: FBScreenshotImageFormat)
  case unreadableImageData
  case unknownImageDimensions
  case decodingFailed
  case compressionQualityOutOfRange(Double)
}

extension FBScreenshotRenderError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .croppingFailed(cropRect, sourceSize):
      return "Failed to crop an image of \(Int(sourceSize.width))x\(Int(sourceSize.height)) pixels to \(cropRect)"
    case let .contextCreationFailed(size):
      return "Failed to create a drawing context of \(Int(size.width))x\(Int(size.height)) pixels"
    case let .scalingFailed(size):
      return "Failed to scale an image to \(Int(size.width))x\(Int(size.height)) pixels"
    case let .destinationCreationFailed(format):
      return "Failed to create an image destination for \(format.rawValue)"
    case let .encodingFailed(format):
      return "Failed to encode an image as \(format.rawValue)"
    case .unreadableImageData:
      return "Captured bytes are not a readable image"
    case .unknownImageDimensions:
      return "Captured image does not report its dimensions"
    case .decodingFailed:
      return "Failed to decode the captured image"
    case let .compressionQualityOutOfRange(quality):
      return "JPEG compression quality \(quality) is not in the range (0, 1]"
    }
  }
}

/// Applies a resolved `FBScreenshotPlan` to a captured image and encodes the result.
///
/// This is the generic path: it works on any `CGImage`, whichever target produced it, so the
/// simulator, device and Mac paths cannot disagree about what a request means. A target that can do
/// better than cropping and resampling an already-rasterised image -- the simulator can, by folding
/// the transform into the render it was going to do anyway -- is free to, so long as it produces the
/// same pixels.
public enum FBScreenshotRenderer {

  /// Transforms and encodes `image` as `plan` and `encoding` describe.
  ///
  /// - Parameter screenScale: reported back on the result so a caller can convert between points and
  ///   pixels itself; it does not affect the render, which `plan` has already resolved to pixels.
  public static func render(
    _ image: CGImage,
    plan: FBScreenshotPlan,
    encoding: FBScreenshotEncoding,
    screenScale: Double?
  ) throws -> FBScreenshotResult {
    try render(
      transformed: try transform(image, plan: plan),
      sourceSize: CGSize(width: image.width, height: image.height),
      encoding: encoding,
      screenScale: screenScale
    )
  }

  /// Encodes an image whose plan has already been applied, and describes it.
  ///
  /// This is for a target that can transform during capture rather than after it -- the simulator
  /// folds the crop and scale into the render it was going to do anyway -- and so arrives holding
  /// the finished pixels and the size they were cut from, with no image left to transform.
  public static func render(
    transformed image: CGImage,
    sourceSize: CGSize,
    encoding: FBScreenshotEncoding,
    screenScale: Double?
  ) throws -> FBScreenshotResult {
    FBScreenshotResult(
      imageData: try encode(image, encoding: encoding),
      format: encoding.format,
      size: CGSize(width: image.width, height: image.height),
      sourceSize: sourceSize,
      screenScale: screenScale
    )
  }

  /// Applies `configuration` to an image that arrives already encoded, as a physical device's does:
  /// the capture comes off the wire as a finished file, so there is no framebuffer to transform.
  ///
  /// A request that asks for exactly what the device already sent is answered with those bytes,
  /// untouched. That is not only cheaper than a decode and re-encode round trip, it is lossless --
  /// re-encoding a PNG would change the bytes for no reason, and doing it via a drawing context
  /// would flatten the source's color space into the context's.
  public static func render(
    encoded data: Data,
    configuration: FBScreenshotConfiguration,
    screenScale: Double?
  ) throws -> FBScreenshotResult {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
      throw FBScreenshotRenderError.unreadableImageData
    }
    // Read the dimensions from the header. This does not decode the pixels, so the passthrough below
    // stays as cheap as returning the bytes.
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0
    else {
      throw FBScreenshotRenderError.unknownImageDimensions
    }
    let sourceSize = CGSize(width: width, height: height)
    let plan = try FBScreenshotGeometry.plan(for: configuration, sourceSize: sourceSize, screenScale: screenScale)

    // Only PNG passes through. It is lossless and takes no encoder options, so bytes already in that
    // container are exactly what a re-encode would have been asked to produce. JPEG carries a
    // quality this image cannot be known to have been encoded at, and the TIFF case promises no
    // compression, which the source is not known to honor.
    if plan.isIdentity, configuration.encoding == .png, CGImageSourceGetType(source) == UTType.png.identifier as CFString {
      return FBScreenshotResult(
        imageData: data,
        format: .png,
        size: sourceSize,
        sourceSize: sourceSize,
        screenScale: screenScale
      )
    }

    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      throw FBScreenshotRenderError.decodingFailed
    }
    return try render(image, plan: plan, encoding: configuration.encoding, screenScale: screenScale)
  }

  /// Crops and scales `image` as `plan` describes, in that order.
  public static func transform(_ image: CGImage, plan: FBScreenshotPlan) throws -> CGImage {
    var result = image
    if let cropRect = plan.cropRect {
      guard let cropped = result.cropping(to: cropRect) else {
        throw FBScreenshotRenderError.croppingFailed(
          cropRect: cropRect,
          sourceSize: CGSize(width: result.width, height: result.height)
        )
      }
      result = cropped
    }
    // Compare the dimensions rather than the factor: a factor that rounds back to the size already
    // in hand is a resample that would cost time to change nothing.
    if Int(plan.outputSize.width) != result.width || Int(plan.outputSize.height) != result.height {
      result = try scale(result, to: plan.outputSize)
    }
    return result
  }

  /// Resamples `image` to `size` on the CPU.
  static func scale(_ image: CGImage, to size: CGSize) throws -> CGImage {
    let width = Int(size.width)
    let height = Int(size.height)
    // Draw into a known-good 8-bit BGRA context rather than one derived from the source. A CGImage
    // can carry a bit layout CGContext refuses to construct -- indexed or non-RGB color spaces, 16
    // bits per component, alpha arrangements with no matching context -- and screenshots arrive in
    // enough shapes across simulator, device and Mac that deriving the layout means occasionally
    // failing to scale an image that is otherwise fine.
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
      )
    else {
      throw FBScreenshotRenderError.contextCreationFailed(size: size)
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let scaled = context.makeImage() else {
      throw FBScreenshotRenderError.scalingFailed(size: size)
    }
    return scaled
  }

  /// Encodes `image` in `encoding`.
  ///
  /// The JPEG quality is checked here rather than at the type. `FBScreenshotEncoding.jpeg(quality:)`
  /// is a case a Swift caller constructs directly, with no initializer to intercept, and ImageIO
  /// silently clamps whatever it is given -- so an out-of-range quality would otherwise be a
  /// successful screenshot at a quality nobody asked for. This is the one place every encode passes
  /// through.
  public static func encode(_ image: CGImage, encoding: FBScreenshotEncoding) throws -> Data {
    if let quality = encoding.compressionQuality, !(quality > 0 && quality <= 1) {
      throw FBScreenshotRenderError.compressionQualityOutOfRange(quality)
    }
    let format = encoding.format
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, format.contentType.identifier as CFString, 1, nil) else {
      throw FBScreenshotRenderError.destinationCreationFailed(format: format)
    }
    var properties: [CFString: Any] = [:]
    switch encoding {
    case .png:
      break
    case .tiff:
      // Uncompressed TIFF: preserve the pixels and color space with no codec cost.
      properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: 1]
    case let .jpeg(quality):
      properties[kCGImageDestinationLossyCompressionQuality] = quality
    }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw FBScreenshotRenderError.encodingFailed(format: format)
    }
    return data as Data
  }
}

extension FBScreenshotImageFormat {
  /// The type ImageIO knows this format by.
  public var contentType: UTType {
    switch self {
    case .png:
      return .png
    case .jpeg:
      return .jpeg
    case .tiff:
      return .tiff
    }
  }
}
