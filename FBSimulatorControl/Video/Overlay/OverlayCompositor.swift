/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreImage
import CoreVideo
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

enum OverlayCompositorError: Error, LocalizedError {
  case failedToCreateCGImage
  case failedToEncodePNG

  var errorDescription: String? {
    switch self {
    case .failedToCreateCGImage:
      return "Failed to create CGImage from pixel buffer"
    case .failedToEncodePNG:
      return "Failed to encode PNG"
    }
  }
}

/// Composites a stream's overlay over its source frames, and pads them out to the edge insets, on
/// the GPU. Produces frames at the encoder's output size — the same `VideoOutputDimensions` the
/// encoder was created for, since a frame of any other size distorts the output.
///
/// Confined to the stream actor: `configure` runs at every mount, `composite` at every push, and
/// `overlayBuffer` is set from `updateOverlayBuffer`.
final class OverlayCompositor {
  let edgeInsets: VideoStreamEdgeInsets
  /// The overlay to draw over every frame, if any. The renderer may update the buffer's contents in
  /// place between pushes.
  var overlayBuffer: CVPixelBuffer?

  private var context: CIContext?
  private var pool: CVPixelBufferPool?
  private(set) var outputWidth = 0
  private(set) var outputHeight = 0

  init(edgeInsets: VideoStreamEdgeInsets) {
    self.edgeInsets = edgeInsets
  }

  private var hasInsets: Bool {
    edgeInsets.top + edgeInsets.bottom + edgeInsets.left + edgeInsets.right > 0
  }

  /// Sizes the output for a newly mounted source. The Core Image context is created once and kept
  /// (its GPU pipeline is expensive to build); the pool is remade for the new size.
  func configure(sourceWidth: Int, sourceHeight: Int, scaleFactor: Double?) {
    if context == nil {
      if let device = MTLCreateSystemDefaultDevice() {
        context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
      } else {
        context = CIContext(options: [.cacheIntermediates: false])
      }
    }
    let dimensions = VideoOutputDimensions.calculate(
      sourceWidth: sourceWidth, sourceHeight: sourceHeight, scaleFactor: scaleFactor, edgeInsets: edgeInsets)
    outputWidth = dimensions.width
    outputHeight = dimensions.height
    let attributes: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: outputWidth,
      kCVPixelBufferHeightKey as String: outputHeight,
      kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
    ]
    var pool: CVPixelBufferPool?
    CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
    self.pool = pool
  }

  /// Releases the pool and the overlay. The context is kept for a later `configure`.
  func reset() {
    pool = nil
    overlayBuffer = nil
  }

  /// The frame to encode: the source composited with the overlay and insets into a pooled output
  /// buffer, or the source itself when there is nothing to composite (or the pool has nothing to give).
  func composite(_ source: CVPixelBuffer) -> CVPixelBuffer {
    guard let image = compositedImage(of: source), let pool, let context else {
      return source
    }
    var output: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output) == kCVReturnSuccess, let output else {
      return source
    }
    context.render(image, to: output)
    return output
  }

  /// A PNG of the source with the overlay composited, rendered straight to a `CGImage` rather than
  /// through the pool.
  func screenshotPNG(of source: CVPixelBuffer) throws -> Data {
    let image = compositedImage(of: source) ?? CIImage(cvPixelBuffer: source)
    let context = self.context ?? CIContext()
    guard let cgImage = context.createCGImage(image, from: image.extent) else {
      throw OverlayCompositorError.failedToCreateCGImage
    }
    let png = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(png as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
      throw OverlayCompositorError.failedToEncodePNG
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw OverlayCompositorError.failedToEncodePNG
    }
    return png as Data
  }

  /// The source scaled into the inset frame with the overlay over it; nil when neither insets nor an
  /// overlay call for compositing, or before `configure`.
  private func compositedImage(of source: CVPixelBuffer) -> CIImage? {
    guard hasInsets || overlayBuffer != nil, context != nil, pool != nil else {
      return nil
    }
    var sourceImage = CIImage(cvPixelBuffer: source)

    // Core Image's origin is bottom-left: scale the source to the inset-free width, then move it up
    // and right by the bottom and left insets.
    let sourceWidth = CVPixelBufferGetWidth(source)
    let targetWidth = outputWidth - Int(edgeInsets.left) - Int(edgeInsets.right)
    if targetWidth != sourceWidth && sourceWidth > 0 {
      let scale = CGFloat(targetWidth) / CGFloat(sourceWidth)
      sourceImage = sourceImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
    if edgeInsets.left > 0 || edgeInsets.bottom > 0 {
      sourceImage = sourceImage.transformed(by: CGAffineTransform(translationX: CGFloat(edgeInsets.left), y: CGFloat(edgeInsets.bottom)))
    }
    guard let overlayBuffer else {
      return sourceImage
    }
    return CIImage(cvPixelBuffer: overlayBuffer).composited(over: sourceImage)
  }
}
