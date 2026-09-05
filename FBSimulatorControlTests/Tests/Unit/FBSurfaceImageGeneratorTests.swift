/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
@testable import FBSimulatorControl
import Foundation
import IOSurface
import XCTest

final class FBSurfaceImageGeneratorTests: XCTestCase {

  private let surfaceSize = CGSize(width: 64, height: 32)

  /// A surface whose pixels vary along both axes, so an image that has been flipped or transposed
  /// looks different from one that has not.
  private func generator() throws -> FBSurfaceImageGenerator {
    let surface = try makeTestIOSurface(width: 64, height: 32) { x, y in
      (b: UInt8(x * 4), g: UInt8(y * 8), r: 0, a: 255)
    }
    let generator = FBSurfaceImageGenerator(purpose: "test", logger: nil)
    generator.updateSurface(surface)
    return generator
  }

  /// Reads an image back as raw BGRA, so two images can be compared by their pixels rather than by
  /// their dimensions alone.
  private func pixels(of image: CGImage) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try bytes.withUnsafeMutableBytes { buffer in
      guard
        let context = CGContext(
          data: buffer.baseAddress,
          width: image.width,
          height: image.height,
          bitsPerComponent: 8,
          bytesPerRow: image.width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
      else {
        throw XCTSkip("Could not create a readback context")
      }
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
  }

  private func render(
    _ configuration: FBScreenshotConfiguration,
    screenScale: Double? = nil,
    generator: FBSurfaceImageGenerator? = nil
  ) throws -> FBSurfaceImage {
    let generator = try generator ?? self.generator()
    return try XCTUnwrap(generator.image(configuration: configuration, screenScale: screenScale))
  }

  // MARK: - No surface

  func testNoSurfaceRendersNothing() throws {
    let generator = FBSurfaceImageGenerator(purpose: "test", logger: nil)
    XCTAssertNil(try generator.image())
    XCTAssertNil(try generator.image(configuration: FBScreenshotConfiguration(), screenScale: nil))
  }

  // MARK: - Identity

  func testDefaultConfigurationRendersTheWholeSurface() throws {
    let rendered = try render(FBScreenshotConfiguration())
    XCTAssertEqual(rendered.sourceSize, surfaceSize)
    XCTAssertEqual(rendered.image.width, 64)
    XCTAssertEqual(rendered.image.height, 32)
  }

  func testBareImageMatchesTheDefaultConfiguration() throws {
    let generator = try generator()
    let bare = try XCTUnwrap(generator.image())
    let configured = try render(FBScreenshotConfiguration(), generator: generator)
    XCTAssertEqual(try pixels(of: bare), try pixels(of: configured.image))
  }

  // MARK: - Crop orientation

  /// Core Image measures from the bottom left while a crop rect is in top-left pixels.
  /// `CGImage.cropping` is unambiguously top-left, so it is the reference for the flip.
  func testCropMatchesTheSameRegionCutFromTheFullRender() throws {
    let generator = try generator()
    let full = try render(FBScreenshotConfiguration(), generator: generator).image

    for cropRect in [
      CGRect(x: 0, y: 0, width: 16, height: 8),
      CGRect(x: 48, y: 0, width: 16, height: 8),
      CGRect(x: 0, y: 24, width: 16, height: 8),
      CGRect(x: 20, y: 9, width: 13, height: 7),
    ] {
      let cropped = try render(FBScreenshotConfiguration(cropRect: cropRect), generator: generator)
      let expected = try XCTUnwrap(full.cropping(to: cropRect))
      XCTAssertEqual(cropped.image.width, Int(cropRect.width), "\(cropRect)")
      XCTAssertEqual(cropped.image.height, Int(cropRect.height), "\(cropRect)")
      XCTAssertEqual(try pixels(of: cropped.image), try pixels(of: expected), "\(cropRect)")
      XCTAssertEqual(cropped.sourceSize, surfaceSize, "\(cropRect)")
    }
  }

  func testTheFixturePatternWouldExposeAFlip() throws {
    let generator = try generator()
    let topLeft = try render(FBScreenshotConfiguration(cropRect: CGRect(x: 0, y: 0, width: 16, height: 8)), generator: generator)
    let bottomLeft = try render(FBScreenshotConfiguration(cropRect: CGRect(x: 0, y: 24, width: 16, height: 8)), generator: generator)
    let topRight = try render(FBScreenshotConfiguration(cropRect: CGRect(x: 48, y: 0, width: 16, height: 8)), generator: generator)
    XCTAssertNotEqual(try pixels(of: topLeft.image), try pixels(of: bottomLeft.image))
    XCTAssertNotEqual(try pixels(of: topLeft.image), try pixels(of: topRight.image))
  }

  func testCropInPointsUsesTheScreenScale() throws {
    let generator = try generator()
    let points = try render(
      FBScreenshotConfiguration(cropRect: CGRect(x: 4, y: 2, width: 8, height: 4), unit: .points),
      screenScale: 2,
      generator: generator
    )
    let equivalent = try render(
      FBScreenshotConfiguration(cropRect: CGRect(x: 8, y: 4, width: 16, height: 8)),
      generator: generator
    )
    XCTAssertEqual(try pixels(of: points.image), try pixels(of: equivalent.image))
  }

  func testPointsWithoutAScreenScaleIsRejected() throws {
    let generator = try generator()
    XCTAssertThrowsError(
      try generator.image(
        configuration: FBScreenshotConfiguration(cropRect: CGRect(x: 0, y: 0, width: 8, height: 4), unit: .points),
        screenScale: nil
      )
    ) { error in
      XCTAssertEqual(error as? FBScreenshotGeometryError, .screenScaleUnknown)
    }
  }

  // MARK: - Scale

  /// An odd source must not come back a pixel short: the read-out uses the planned size, not
  /// the filter's output extent.
  func testScaleProducesExactlyThePlannedSize() throws {
    let generator = try generator()
    let cases: [(FBScreenshotScale, CGSize)] = [
      (.factor(0.5), CGSize(width: 32, height: 16)),
      (.factor(0.25), CGSize(width: 16, height: 8)),
      (.factor(0.3), CGSize(width: 19, height: 10)),
      (.fit(maxWidth: 20, maxHeight: nil), CGSize(width: 20, height: 10)),
      (.fit(maxWidth: nil, maxHeight: 7), CGSize(width: 14, height: 7)),
      (.fit(maxWidth: 200, maxHeight: 200), surfaceSize),
    ]
    for (scale, expected) in cases {
      let rendered = try render(FBScreenshotConfiguration(scale: scale), generator: generator)
      XCTAssertEqual(CGSize(width: rendered.image.width, height: rendered.image.height), expected, "\(scale)")
      XCTAssertEqual(rendered.sourceSize, surfaceSize, "\(scale)")
    }
  }

  /// The scale applies to the cropped region, not to the surface.
  func testCropThenScale() throws {
    let configuration = FBScreenshotConfiguration(
      cropRect: CGRect(x: 8, y: 4, width: 32, height: 16),
      scale: .factor(0.5)
    )
    let rendered = try render(configuration)
    XCTAssertEqual(rendered.image.width, 16)
    XCTAssertEqual(rendered.image.height, 8)
    XCTAssertEqual(rendered.sourceSize, surfaceSize)
  }

  func testScaledRenderKeepsTheWholeRegion() throws {
    let generator = try generator()
    let full = try render(FBScreenshotConfiguration(), generator: generator).image
    let halved = try render(FBScreenshotConfiguration(scale: .factor(0.5)), generator: generator).image

    // Sample the far corners. The surface's blue ramps along x and its green along y, so a render
    // that dropped or mirrored an edge would not carry both ends of both ramps.
    let fullPixels = try pixels(of: full)
    let halvedPixels = try pixels(of: halved)
    func blueGreen(_ bytes: [UInt8], width: Int, x: Int, y: Int) -> (UInt8, UInt8) {
      let offset = (y * width + x) * 4
      return (bytes[offset], bytes[offset + 1])
    }
    let fullTopLeft = blueGreen(fullPixels, width: 64, x: 0, y: 0)
    let fullBottomRight = blueGreen(fullPixels, width: 64, x: 63, y: 31)
    let halvedTopLeft = blueGreen(halvedPixels, width: 32, x: 0, y: 0)
    let halvedBottomRight = blueGreen(halvedPixels, width: 32, x: 31, y: 15)

    // Resampling moves the exact values, so compare the direction of each ramp rather than bytes.
    XCTAssertLessThan(fullTopLeft.0, fullBottomRight.0)
    XCTAssertLessThan(fullTopLeft.1, fullBottomRight.1)
    XCTAssertLessThan(halvedTopLeft.0, halvedBottomRight.0)
    XCTAssertLessThan(halvedTopLeft.1, halvedBottomRight.1)
  }
}
