/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class FBScreenshotConfigurationTests: XCTestCase {

  /// A 3x retina phone screen: 828x1792 pixels, 276x597 points.
  private let sourceSize = CGSize(width: 828, height: 1792)
  private let screenScale = 3.0

  /// `.some(nil)` asks for a target that does not report a screen scale; omitting the argument uses
  /// the 3x default.
  private func plan(
    _ configuration: FBScreenshotConfiguration,
    sourceSize: CGSize? = nil,
    screenScale: Double?? = nil
  ) throws -> FBScreenshotPlan {
    try FBScreenshotGeometry.plan(
      for: configuration,
      sourceSize: sourceSize ?? self.sourceSize,
      screenScale: screenScale ?? self.screenScale
    )
  }

  private func assertThrows(
    _ expected: FBScreenshotGeometryError,
    _ configuration: FBScreenshotConfiguration,
    sourceSize: CGSize? = nil,
    screenScale: Double?? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(
      try plan(configuration, sourceSize: sourceSize, screenScale: screenScale),
      file: file,
      line: line
    ) { error in
      XCTAssertEqual(error as? FBScreenshotGeometryError, expected, file: file, line: line)
    }
  }

  // MARK: - Defaults

  func testDefaultConfigurationIsAnIdentityTransform() throws {
    let result = try plan(FBScreenshotConfiguration())
    XCTAssertTrue(result.isIdentity)
    XCTAssertNil(result.cropRect)
    XCTAssertEqual(result.scaleFactor, 1)
    XCTAssertEqual(result.outputSize, sourceSize)
  }

  func testDefaultEncodingIsPNG() {
    XCTAssertEqual(FBScreenshotConfiguration().encoding, .png)
    XCTAssertEqual(FBScreenshotConfiguration().unit, .pixels)
  }

  // MARK: - Encoding

  func testCompressionQualityExistsOnlyOnJPEG() {
    XCTAssertNil(FBScreenshotEncoding.png.compressionQuality)
    XCTAssertNil(FBScreenshotEncoding.tiff.compressionQuality)
    XCTAssertEqual(FBScreenshotEncoding.jpeg(quality: 0.6).compressionQuality, 0.6)
  }

  func testEncodingFormats() {
    XCTAssertEqual(FBScreenshotEncoding.png.format, .png)
    XCTAssertEqual(FBScreenshotEncoding.tiff.format, .tiff)
    XCTAssertEqual(FBScreenshotEncoding.jpeg(quality: 0.8).format, .jpeg)
  }

  // MARK: - Scale factor

  func testScaleFactorHalvesBothDimensions() throws {
    let result = try plan(FBScreenshotConfiguration(scale: .factor(0.5)))
    XCTAssertEqual(result.scaleFactor, 0.5)
    XCTAssertEqual(result.outputSize, CGSize(width: 414, height: 896))
    XCTAssertFalse(result.isIdentity)
  }

  func testScaleFactorOfOneIsAnIdentityTransform() throws {
    let result = try plan(FBScreenshotConfiguration(scale: .factor(1)))
    XCTAssertTrue(result.isIdentity)
  }

  func testScaleFactorMustBeInRange() {
    assertThrows(.scaleFactorOutOfRange(0), FBScreenshotConfiguration(scale: .factor(0)))
    assertThrows(.scaleFactorOutOfRange(-0.5), FBScreenshotConfiguration(scale: .factor(-0.5)))
    assertThrows(.scaleFactorOutOfRange(1.5), FBScreenshotConfiguration(scale: .factor(1.5)))
  }

  // MARK: - Fit

  func testFitOnWidthAlone() throws {
    let result = try plan(FBScreenshotConfiguration(scale: .fit(maxWidth: 414, maxHeight: nil)))
    XCTAssertEqual(result.scaleFactor, 0.5)
    XCTAssertEqual(result.outputSize, CGSize(width: 414, height: 896))
  }

  func testFitOnHeightAlone() throws {
    let result = try plan(FBScreenshotConfiguration(scale: .fit(maxWidth: nil, maxHeight: 896)))
    XCTAssertEqual(result.scaleFactor, 0.5)
    XCTAssertEqual(result.outputSize, CGSize(width: 414, height: 896))
  }

  /// A tall screen inside a square box is bounded by its height, not its width.
  func testMoreRestrictiveFitBoundWins() throws {
    let result = try plan(FBScreenshotConfiguration(scale: .fit(maxWidth: 400, maxHeight: 400)))
    XCTAssertEqual(result.scaleFactor, 400.0 / 1792.0, accuracy: 1e-12)
    XCTAssertEqual(result.outputSize, CGSize(width: 185, height: 400))
  }

  func testFitNeverUpscales() throws {
    let result = try plan(FBScreenshotConfiguration(scale: .fit(maxWidth: 4000, maxHeight: 4000)))
    XCTAssertEqual(result.scaleFactor, 1)
    XCTAssertEqual(result.outputSize, sourceSize)
    XCTAssertTrue(result.isIdentity)
  }

  func testFitNeedsABound() {
    assertThrows(.fitBoundsEmpty, FBScreenshotConfiguration(scale: .fit(maxWidth: nil, maxHeight: nil)))
  }

  func testFitBoundsMustBePositive() {
    assertThrows(.fitBoundNotPositive(0), FBScreenshotConfiguration(scale: .fit(maxWidth: 0, maxHeight: nil)))
    assertThrows(.fitBoundNotPositive(-100), FBScreenshotConfiguration(scale: .fit(maxWidth: nil, maxHeight: -100)))
  }

  /// A bound so tight the result is unreadable is still a legal request: there is no non-arbitrary
  /// cutoff between "small" and "too small", and the pixel floor keeps it from degenerating.
  func testExtremelyTightFitBoundProducesTheSmallestHonestImage() throws {
    let result = try plan(FBScreenshotConfiguration(scale: .fit(maxWidth: 1, maxHeight: nil)))
    XCTAssertEqual(result.outputSize, CGSize(width: 1, height: 2))
  }

  // MARK: - Units

  func testFitBoundsInPointsAreResolvedAgainstTheScreenScale() throws {
    // 138 points on a 3x screen is 414 pixels, half of the 828-pixel width.
    let result = try plan(FBScreenshotConfiguration(scale: .fit(maxWidth: 138, maxHeight: nil), unit: .points))
    XCTAssertEqual(result.scaleFactor, 0.5)
    XCTAssertEqual(result.outputSize, CGSize(width: 414, height: 896))
  }

  func testCropInPointsIsResolvedAgainstTheScreenScale() throws {
    let configuration = FBScreenshotConfiguration(cropRect: CGRect(x: 10, y: 20, width: 30, height: 40), unit: .points)
    let result = try plan(configuration)
    XCTAssertEqual(result.cropRect, CGRect(x: 30, y: 60, width: 90, height: 120))
    XCTAssertEqual(result.outputSize, CGSize(width: 90, height: 120))
  }

  func testPointsAndPixelsAgreeOnAOnexScreen() throws {
    let configuration = FBScreenshotConfiguration(cropRect: CGRect(x: 10, y: 20, width: 30, height: 40), unit: .points)
    let result = try plan(configuration, sourceSize: CGSize(width: 400, height: 600), screenScale: 1)
    XCTAssertEqual(result.cropRect, CGRect(x: 10, y: 20, width: 30, height: 40))
  }

  /// A physical device does not report a screen scale, so points cannot be resolved there. Guessing
  /// 1 would answer a request for one region with a different, much smaller one, and report success.
  func testPointsAgainstATargetWithNoScreenScaleIsRejected() {
    assertThrows(
      .screenScaleUnknown,
      FBScreenshotConfiguration(cropRect: CGRect(x: 0, y: 0, width: 10, height: 10), unit: .points),
      screenScale: .some(nil)
    )
    assertThrows(
      .screenScaleUnknown,
      FBScreenshotConfiguration(scale: .fit(maxWidth: 100, maxHeight: nil), unit: .points),
      screenScale: .some(nil)
    )
  }

  /// A unit describes measurements, and a full-screen native capture has none. Resolving the scale
  /// before knowing that would fail a request for the whole screen on a target that cannot report
  /// one -- for a conversion that request was never going to perform.
  func testPointsWithNothingToConvertNeedsNoScreenScale() throws {
    let result = try plan(FBScreenshotConfiguration(unit: .points), screenScale: .some(nil))
    XCTAssertNil(result.cropRect)
    XCTAssertEqual(result.scaleFactor, 1)
    XCTAssertEqual(result.outputSize, sourceSize)
    XCTAssertTrue(result.isIdentity)
  }

  /// A scale factor is a ratio rather than a measurement, so it is the same number in either unit.
  func testPointsWithOnlyAScaleFactorNeedsNoScreenScale() throws {
    let configuration = FBScreenshotConfiguration(scale: .factor(0.5), unit: .points)
    let result = try plan(configuration, screenScale: .some(nil))
    XCTAssertNil(result.cropRect)
    XCTAssertEqual(result.outputSize, CGSize(width: 414, height: 896))
  }

  func testOnlyMeasurementsInPointsRequireAScreenScale() {
    XCTAssertFalse(FBScreenshotConfiguration(unit: .points).requiresScreenScale)
    XCTAssertFalse(FBScreenshotConfiguration(scale: .factor(0.5), unit: .points).requiresScreenScale)
    XCTAssertFalse(
      FBScreenshotConfiguration(cropRect: CGRect(x: 0, y: 0, width: 10, height: 10)).requiresScreenScale
    )
    XCTAssertFalse(FBScreenshotConfiguration(scale: .fit(maxWidth: 100, maxHeight: nil)).requiresScreenScale)
    XCTAssertTrue(
      FBScreenshotConfiguration(cropRect: CGRect(x: 0, y: 0, width: 10, height: 10), unit: .points)
        .requiresScreenScale
    )
    XCTAssertTrue(
      FBScreenshotConfiguration(scale: .fit(maxWidth: 100, maxHeight: nil), unit: .points).requiresScreenScale
    )
  }

  /// Pixels are the default and need no screen scale, so they work on every target.
  func testPixelsNeedNoScreenScale() throws {
    let configuration = FBScreenshotConfiguration(
      cropRect: CGRect(x: 0, y: 0, width: 400, height: 400),
      scale: .factor(0.5)
    )
    let result = try plan(configuration, screenScale: .some(nil))
    XCTAssertEqual(result.cropRect, CGRect(x: 0, y: 0, width: 400, height: 400))
    XCTAssertEqual(result.outputSize, CGSize(width: 200, height: 200))
  }

  func testNonPositiveScreenScaleIsTreatedAsUnknown() {
    assertThrows(
      .screenScaleUnknown,
      FBScreenshotConfiguration(cropRect: CGRect(x: 0, y: 0, width: 10, height: 10), unit: .points),
      screenScale: 0
    )
  }

  func testCropInPixelsIgnoresTheScreenScale() throws {
    let configuration = FBScreenshotConfiguration(cropRect: CGRect(x: 10, y: 20, width: 30, height: 40))
    let result = try plan(configuration)
    XCTAssertEqual(result.cropRect, CGRect(x: 10, y: 20, width: 30, height: 40))
  }

  // MARK: - Crop

  func testCropIsRoundedOutToWholePixels() throws {
    let configuration = FBScreenshotConfiguration(cropRect: CGRect(x: 10.4, y: 20.6, width: 30.2, height: 40.9))
    let result = try plan(configuration)
    XCTAssertEqual(result.cropRect, CGRect(x: 10, y: 20, width: 31, height: 42))
  }

  /// An element near the edge of the screen is a normal thing to crop around, so an overhanging
  /// rect yields the part that exists rather than an error.
  func testCropOverhangingTheScreenIsClamped() throws {
    let configuration = FBScreenshotConfiguration(cropRect: CGRect(x: 800, y: 1700, width: 100, height: 200))
    let result = try plan(configuration)
    XCTAssertEqual(result.cropRect, CGRect(x: 800, y: 1700, width: 28, height: 92))
    XCTAssertEqual(result.outputSize, CGSize(width: 28, height: 92))
  }

  func testCropEntirelyOffTheScreenIsRejected() {
    let cropRect = CGRect(x: 900, y: 0, width: 100, height: 100)
    assertThrows(
      .cropOutsideBounds(cropRect: cropRect, sourceSize: sourceSize),
      FBScreenshotConfiguration(cropRect: cropRect)
    )
  }

  func testCropWithNoExtentIsRejected() {
    let zeroWidth = CGRect(x: 0, y: 0, width: 0, height: 100)
    assertThrows(.cropExtentNotPositive(zeroWidth), FBScreenshotConfiguration(cropRect: zeroWidth))
    let negativeHeight = CGRect(x: 0, y: 0, width: 100, height: -10)
    assertThrows(.cropExtentNotPositive(negativeHeight), FBScreenshotConfiguration(cropRect: negativeHeight))
  }

  // MARK: - Crop and scale together

  /// Scale applies to what survives the crop, not to the whole screen -- otherwise a caller
  /// bounding a cropped region would get a factor computed from dimensions it discarded.
  func testScaleAppliesToTheCroppedRegion() throws {
    let configuration = FBScreenshotConfiguration(
      cropRect: CGRect(x: 0, y: 0, width: 400, height: 400),
      scale: .fit(maxWidth: 200, maxHeight: nil)
    )
    let result = try plan(configuration)
    XCTAssertEqual(result.cropRect, CGRect(x: 0, y: 0, width: 400, height: 400))
    XCTAssertEqual(result.scaleFactor, 0.5)
    XCTAssertEqual(result.outputSize, CGSize(width: 200, height: 200))
  }

  func testScaleAppliesToTheClampedCropNotTheRequestedOne() throws {
    let configuration = FBScreenshotConfiguration(
      cropRect: CGRect(x: 428, y: 0, width: 800, height: 400),
      scale: .factor(0.5)
    )
    let result = try plan(configuration)
    XCTAssertEqual(result.cropRect, CGRect(x: 428, y: 0, width: 400, height: 400))
    XCTAssertEqual(result.outputSize, CGSize(width: 200, height: 200))
  }

  // MARK: - Rounding

  /// Half rounds up, not to even, matching the client-side resizers callers are migrating from.
  func testOutputRoundsHalfUp() {
    XCTAssertEqual(FBScreenshotGeometry.outputSize(baseSize: CGSize(width: 5, height: 7), factor: 0.5), CGSize(width: 3, height: 4))
    XCTAssertEqual(FBScreenshotGeometry.roundToPixels(2.5), 3)
    XCTAssertEqual(FBScreenshotGeometry.roundToPixels(3.5), 4)
    XCTAssertEqual(FBScreenshotGeometry.roundToPixels(2.49), 2)
  }

  /// A zero-dimension image is not a smaller image, it is a broken one.
  func testOutputIsFlooredAtOnePixelPerSide() {
    let size = FBScreenshotGeometry.outputSize(baseSize: CGSize(width: 100, height: 100), factor: 0.001)
    XCTAssertEqual(size, CGSize(width: 1, height: 1))
  }

  // MARK: - Source

  func testEmptySourceIsRejected() {
    assertThrows(.sourceSizeNotPositive(.zero), FBScreenshotConfiguration(), sourceSize: .zero)
  }
}
