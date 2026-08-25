/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
@testable import FBControlCore
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class FBScreenshotRendererTests: XCTestCase {

  /// The fixture is a 988x388 PNG, standing in for a capture that arrives already encoded.
  private let fixtureSize = CGSize(width: 988, height: 388)

  private func fixtureData() throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: TestFixtures.photo0Path))
  }

  private func fixtureImage() throws -> CGImage {
    let data = try fixtureData()
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
  }

  /// Reads back what was actually encoded, rather than trusting the reported dimensions.
  private func decode(_ data: Data) throws -> (type: UTType, size: CGSize) {
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let identifier = try XCTUnwrap(CGImageSourceGetType(source) as String?)
    let type = try XCTUnwrap(UTType(identifier))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    return (type, CGSize(width: image.width, height: image.height))
  }

  private func render(_ configuration: FBScreenshotConfiguration, screenScale: Double? = 2) throws -> FBScreenshotResult {
    try FBScreenshotRenderer.render(encoded: try fixtureData(), configuration: configuration, screenScale: screenScale)
  }

  // MARK: - Passthrough

  func testWholeScreenAsPNGReturnsTheCapturedBytesUntouched() throws {
    let data = try fixtureData()
    let result = try render(FBScreenshotConfiguration())
    XCTAssertEqual(result.imageData, data)
    XCTAssertEqual(result.format, .png)
    XCTAssertEqual(result.size, fixtureSize)
    XCTAssertEqual(result.sourceSize, fixtureSize)
    XCTAssertEqual(result.screenScale, 2)
  }

  /// A different container is a real request, so the bytes cannot be handed back as they are.
  func testWholeScreenInAnotherFormatIsReEncoded() throws {
    let data = try fixtureData()
    for encoding in [FBScreenshotEncoding.jpeg(quality: 0.8), .tiff] {
      let result = try render(FBScreenshotConfiguration(encoding: encoding))
      XCTAssertNotEqual(result.imageData, data)
      XCTAssertEqual(result.format, encoding.format)
      XCTAssertEqual(result.size, fixtureSize)
      let decoded = try decode(result.imageData)
      XCTAssertEqual(decoded.type, encoding.format.contentType)
      XCTAssertEqual(decoded.size, fixtureSize)
    }
  }

  func testATransformDefeatsThePassthrough() throws {
    let data = try fixtureData()
    let result = try render(FBScreenshotConfiguration(scale: .factor(0.5)))
    XCTAssertNotEqual(result.imageData, data)
    XCTAssertEqual(result.format, .png)
  }

  // MARK: - Crop and scale on encoded input

  func testCropOnEncodedInput() throws {
    let result = try render(FBScreenshotConfiguration(cropRect: CGRect(x: 100, y: 50, width: 200, height: 100)))
    XCTAssertEqual(result.size, CGSize(width: 200, height: 100))
    XCTAssertEqual(result.sourceSize, fixtureSize)
    XCTAssertEqual(try decode(result.imageData).size, CGSize(width: 200, height: 100))
  }

  func testScaleOnEncodedInput() throws {
    let result = try render(FBScreenshotConfiguration(scale: .factor(0.5)))
    XCTAssertEqual(result.size, CGSize(width: 494, height: 194))
    XCTAssertEqual(try decode(result.imageData).size, CGSize(width: 494, height: 194))
  }

  func testFitOnEncodedInput() throws {
    let result = try render(FBScreenshotConfiguration(scale: .fit(maxWidth: 247, maxHeight: nil)))
    XCTAssertEqual(result.size, CGSize(width: 247, height: 97))
    XCTAssertEqual(try decode(result.imageData).size, CGSize(width: 247, height: 97))
  }

  func testCropThenScaleOnEncodedInput() throws {
    let configuration = FBScreenshotConfiguration(
      cropRect: CGRect(x: 0, y: 0, width: 400, height: 200),
      scale: .factor(0.5)
    )
    let result = try render(configuration)
    XCTAssertEqual(result.size, CGSize(width: 200, height: 100))
    XCTAssertEqual(try decode(result.imageData).size, CGSize(width: 200, height: 100))
  }

  /// The crop is in points, so a 2x scale doubles it before it reaches the pixels.
  func testCropInPointsOnEncodedInput() throws {
    let configuration = FBScreenshotConfiguration(
      cropRect: CGRect(x: 0, y: 0, width: 100, height: 50),
      unit: .points
    )
    let result = try render(configuration, screenScale: 2)
    XCTAssertEqual(result.size, CGSize(width: 200, height: 100))
  }

  func testPointsWithoutAScreenScaleIsRejectedOnEncodedInput() throws {
    let configuration = FBScreenshotConfiguration(
      cropRect: CGRect(x: 0, y: 0, width: 100, height: 50),
      unit: .points
    )
    XCTAssertThrowsError(try render(configuration, screenScale: nil)) { error in
      XCTAssertEqual(error as? FBScreenshotGeometryError, .screenScaleUnknown)
    }
    XCTAssertNoThrow(try render(FBScreenshotConfiguration(), screenScale: nil))
    // Points with nothing measured in them converts nothing, so it needs no scale either.
    XCTAssertNoThrow(try render(FBScreenshotConfiguration(unit: .points), screenScale: nil))
  }

  func testUnreadableInputIsRejected() {
    let data = Data("not an image".utf8)
    XCTAssertThrowsError(
      try FBScreenshotRenderer.render(encoded: data, configuration: FBScreenshotConfiguration(), screenScale: nil)
    ) { error in
      XCTAssertEqual(error as? FBScreenshotRenderError, .unreadableImageData)
    }
  }

  // MARK: - Transform

  func testTransformIsAnIdentityWhenThePlanIs() throws {
    let image = try fixtureImage()
    let plan = FBScreenshotPlan(cropRect: nil, scaleFactor: 1, outputSize: fixtureSize)
    let transformed = try FBScreenshotRenderer.transform(image, plan: plan)
    XCTAssertTrue(transformed === image)
  }

  func testTransformCropsAndScales() throws {
    let image = try fixtureImage()
    let plan = FBScreenshotPlan(
      cropRect: CGRect(x: 10, y: 20, width: 400, height: 200),
      scaleFactor: 0.25,
      outputSize: CGSize(width: 100, height: 50)
    )
    let transformed = try FBScreenshotRenderer.transform(image, plan: plan)
    XCTAssertEqual(transformed.width, 100)
    XCTAssertEqual(transformed.height, 50)
  }

  /// A factor that rounds back to the size already in hand should not cost a resample.
  func testTransformSkipsAResampleThatWouldChangeNothing() throws {
    let image = try fixtureImage()
    let plan = FBScreenshotPlan(cropRect: nil, scaleFactor: 0.9999, outputSize: fixtureSize)
    let transformed = try FBScreenshotRenderer.transform(image, plan: plan)
    XCTAssertTrue(transformed === image)
  }

  /// The one-pixel floor is a rule of `FBScreenshotGeometry`, not of `FBScreenshotPlan` -- the type
  /// has a public memberwise initializer, so a Swift caller can hand `transform` an output size the
  /// geometry would never have produced. That has to fail with a named error rather than reach Core
  /// Graphics as a zero-sized context.
  func testTransformRejectsAPlanWithNoOutput() throws {
    let image = try fixtureImage()
    for outputSize in [CGSize(width: 0, height: 10), CGSize(width: 10, height: 0), .zero] {
      let plan = FBScreenshotPlan(cropRect: nil, scaleFactor: 1, outputSize: outputSize)
      XCTAssertThrowsError(try FBScreenshotRenderer.transform(image, plan: plan), "\(outputSize)") { error in
        XCTAssertEqual(error as? FBScreenshotRenderError, .contextCreationFailed(size: outputSize), "\(outputSize)")
      }
    }
  }

  // MARK: - Encode

  func testEncodeProducesTheRequestedContainer() throws {
    let image = try fixtureImage()
    for encoding in [FBScreenshotEncoding.png, .tiff, .jpeg(quality: 0.8)] {
      let data = try FBScreenshotRenderer.encode(image, encoding: encoding)
      let decoded = try decode(data)
      XCTAssertEqual(decoded.type, encoding.format.contentType, "\(encoding)")
      XCTAssertEqual(decoded.size, fixtureSize, "\(encoding)")
    }
  }

  func testJPEGQualityChangesTheEncodedSize() throws {
    let image = try fixtureImage()
    let low = try FBScreenshotRenderer.encode(image, encoding: .jpeg(quality: 0.1))
    let high = try FBScreenshotRenderer.encode(image, encoding: .jpeg(quality: 0.95))
    XCTAssertLessThan(low.count, high.count)
  }

  /// ImageIO clamps a quality outside (0, 1] and encodes anyway, which would hand back an image at a
  /// quality nobody asked for and call it a success. A Swift caller can build the case directly, so
  /// the encoder is the only place that sees every one of them.
  func testEncodeRejectsAQualityOutsideTheRange() throws {
    let image = try fixtureImage()
    for quality in [0.0, -0.5, 1.5] {
      let encoding = FBScreenshotEncoding.jpeg(quality: quality)
      XCTAssertThrowsError(try FBScreenshotRenderer.encode(image, encoding: encoding), "\(quality)") { error in
        XCTAssertEqual(error as? FBScreenshotRenderError, .compressionQualityOutOfRange(quality), "\(quality)")
      }
    }
    // NaN compares false against every bound, so it has to be rejected by the shape of the check
    // rather than by a comparison that happens to be true.
    XCTAssertThrowsError(try FBScreenshotRenderer.encode(image, encoding: .jpeg(quality: .nan)))
    XCTAssertNoThrow(try FBScreenshotRenderer.encode(image, encoding: .jpeg(quality: 1)))
  }

  /// The TIFF case exists to be uncompressed, which is only worth having if it is bigger than the
  /// compressed containers rather than quietly being one of them.
  func testTIFFIsUncompressed() throws {
    let image = try fixtureImage()
    let tiff = try FBScreenshotRenderer.encode(image, encoding: .tiff)
    let png = try FBScreenshotRenderer.encode(image, encoding: .png)
    XCTAssertGreaterThan(tiff.count, png.count)
    // At least three bytes per pixel, whether or not the encoder keeps an alpha channel. Anything
    // compressed comes in well under this for a photograph.
    XCTAssertGreaterThan(tiff.count, Int(fixtureSize.width * fixtureSize.height) * 3)
  }
}
