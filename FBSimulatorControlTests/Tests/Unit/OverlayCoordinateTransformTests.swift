/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

/// Tests for FBOverlayCoordinateTransform.
///
/// Device reference: iPhone 11
///   - Screen: 828×1792 pixels, 414×896 points, 2x retina
///   - With --border-top 24 at videoScale=0.5:
///     - scaledBorderTop = 24 * videoScale * retinaScale = 24 * 0.5 * 2.0 = 24 buffer px
///     - buffer = 414×(896 + 24) = 414×920
///     - overlayScale = 0.5 * 2.0 = 1.0
///     - insetCorrection.y = scaledBorderTop - borderTop * overlayScale = 24 - 24 = 0
class FBOverlayCoordinateTransformTests: XCTestCase {

  private func iPhone11Transform(borderBottom: Int = 0, scaledBorderBottom: Int = 0) -> FBOverlayCoordinateTransform {
    // scaledBorderTop = borderTop * videoScale * retinaScale = 24 * 0.5 * 2.0 = 24
    FBOverlayCoordinateTransform(
      screenPixelWidth: 828,
      screenPixelHeight: 1792,
      retinaScale: 2.0,
      videoScale: 0.5,
      borderTop: 24,
      scaledBorderTop: 24,
      borderBottom: borderBottom,
      scaledBorderBottom: scaledBorderBottom
    )
  }

  func testBufferDimensions() {
    let t = iPhone11Transform()
    XCTAssertEqual(t.bufferWidth, 414)
    // 1792 * 0.5 + 24 (scaledBorderTop) = 920
    XCTAssertEqual(t.bufferHeight, 920)
  }

  func testOverlayScale() {
    let t = iPhone11Transform()
    XCTAssertEqual(t.overlayScale, 1.0, accuracy: 0.01)
  }

  func testInsetCorrection() {
    let t = iPhone11Transform()
    // scaledBorderTop(24) - borderTop(24) * overlayScale(1.0) = 0
    XCTAssertEqual(t.insetCorrection.x, 0, accuracy: 0.01)
    XCTAssertEqual(t.insetCorrection.y, 0, accuracy: 0.01)
  }

  // MARK: - Point mapping

  func testBufferPointForClickAtCenter() {
    let t = iPhone11Transform()
    // x: 164 * 1.0 + 0 = 164
    // y: 382 * 1.0 + 0 = 382
    let p = t.bufferPoint(x: 164, y: 382)
    XCTAssertEqual(p.x, 164, accuracy: 0.01)
    XCTAssertEqual(p.y, 382, accuracy: 0.01)
  }

  func testBufferPointAtOrigin() {
    let t = iPhone11Transform()
    let p = t.bufferPoint(x: 0, y: 0)
    XCTAssertEqual(p.x, 0, accuracy: 0.01)
    XCTAssertEqual(p.y, 0, accuracy: 0.01)
  }

  // MARK: - Size mapping

  func testBufferSizeAtScale1() {
    let t = iPhone11Transform()
    let s = t.bufferSize(width: 44, height: 48)
    XCTAssertEqual(s.width, 44, accuracy: 0.01)
    XCTAssertEqual(s.height, 48, accuracy: 0.01)
  }

  // MARK: - Rect

  func testBufferRectNegativeWidthSpansToEdge() {
    let t = iPhone11Transform()
    let r = t.bufferRect(x: 0, y: 24, width: -1, height: 10)
    XCTAssertEqual(r.origin.x, 0, accuracy: 0.01)
    XCTAssertEqual(r.origin.y, 24, accuracy: 0.01) // 24 + 0 = 24
    XCTAssertEqual(r.size.width, 414, accuracy: 1)
    XCTAssertEqual(r.size.height, 10, accuracy: 0.01)
  }

  func testBufferRectPositive() {
    let t = iPhone11Transform()
    let r = t.bufferRect(x: 10, y: 34, width: 100, height: 50)
    XCTAssertEqual(r.origin.x, 10, accuracy: 0.01)
    XCTAssertEqual(r.origin.y, 34, accuracy: 0.01) // 34 + 0 = 34
    XCTAssertEqual(r.size.width, 100, accuracy: 0.01)
    XCTAssertEqual(r.size.height, 50, accuracy: 0.01)
  }

  // MARK: - Translate target

  func testTranslateTarget() {
    let t = iPhone11Transform()
    let p = t.translateTarget(x: 200, y: 500)
    XCTAssertEqual(p.x, 200, accuracy: 0.01)
    XCTAssertEqual(p.y, 500, accuracy: 0.01) // 500 + 0 = 500
  }

  // MARK: - Label layout

  func testLabelOriginIPhone11() {
    let t = iPhone11Transform()
    // overlayScale = 1.0, headerHeight = scaledBorderTop = 24
    let font = CTFontCreateWithName("Monaco" as CFString, t.labelFontSize(8), nil)
    let ascent = CTFontGetAscent(font)
    let descent = CTFontGetDescent(font)
    let origin = t.labelOrigin(padding: 4, ascent: ascent, descent: descent)
    let lineHeight = ascent + descent
    // x = padding * overlayScale + insetCorrection.x = 4 + 0 = 4
    XCTAssertEqual(origin.x, 4.0, accuracy: 0.001)
    // y = centered within visible 24px header, no insetCorrection.y
    let expectedY = (24.0 - lineHeight) / 2 + ascent
    XCTAssertEqual(origin.y, expectedY, accuracy: 0.001)
  }

  func testLabelOriginDoesNotApplyInsetCorrection() {
    // Even when insetCorrection.y is nonzero, labelOrigin doesn't apply it. The label
    // centers within the visible header (= scaledBorderTop), not at logical y=0.
    let t = FBOverlayCoordinateTransform(
      screenPixelWidth: 828, screenPixelHeight: 1792,
      retinaScale: 2.0, videoScale: 0.5,
      borderTop: 24, scaledBorderTop: 12, // intentionally underprovisioned to force insetCorrection.y != 0
      borderBottom: 0, scaledBorderBottom: 0
    )
    XCTAssertEqual(t.insetCorrection.y, -12, accuracy: 0.01)
    let font = CTFontCreateWithName("Monaco" as CFString, t.labelFontSize(8), nil)
    let ascent = CTFontGetAscent(font)
    let descent = CTFontGetDescent(font)
    let origin = t.labelOrigin(padding: 4, ascent: ascent, descent: descent)
    let lineHeight = ascent + descent
    // labelOrigin centers within the visible header (12px), NOT borderTop * overlayScale (24px).
    // insetCorrection.y is NOT applied.
    let expectedY = (12.0 - lineHeight) / 2 + ascent
    XCTAssertEqual(origin.y, expectedY, accuracy: 0.001)
  }

  func testLabelOrigin3xRetina() {
    let t = FBOverlayCoordinateTransform(
      screenPixelWidth: 1170, screenPixelHeight: 2532,
      retinaScale: 3.0, videoScale: 0.5,
      // scaledBorderTop = borderTop * videoScale * retinaScale = 24 * 0.5 * 3.0 = 36
      borderTop: 24, scaledBorderTop: 36,
      borderBottom: 0, scaledBorderBottom: 0
    )
    // overlayScale = 1.5, headerHeight = 36
    XCTAssertEqual(t.overlayScale, 1.5, accuracy: 0.001)
    let font = CTFontCreateWithName("Monaco" as CFString, t.labelFontSize(8), nil)
    let ascent = CTFontGetAscent(font)
    let descent = CTFontGetDescent(font)
    let origin = t.labelOrigin(padding: 4, ascent: ascent, descent: descent)
    let lineHeight = ascent + descent
    // x = 4 * 1.5 = 6
    XCTAssertEqual(origin.x, 6.0, accuracy: 0.001)
    // y = centered within visible 36px header
    let expectedY = (36.0 - lineHeight) / 2 + ascent
    XCTAssertEqual(origin.y, expectedY, accuracy: 0.001)
  }

  func testLabelOriginZeroBorderTop() {
    let t = FBOverlayCoordinateTransform(
      screenPixelWidth: 100, screenPixelHeight: 100,
      retinaScale: 1.0, videoScale: 1.0,
      borderTop: 0, scaledBorderTop: 0,
      borderBottom: 0, scaledBorderBottom: 0
    )
    let font = CTFontCreateWithName("Monaco" as CFString, t.labelFontSize(8), nil)
    let ascent = CTFontGetAscent(font)
    let descent = CTFontGetDescent(font)
    let origin = t.labelOrigin(padding: 4, ascent: ascent, descent: descent)
    // With zero headerHeight, falls back to padding-based positioning
    XCTAssertEqual(origin.x, 4.0, accuracy: 0.001)
    XCTAssertEqual(origin.y, 4.0 + ascent, accuracy: 0.001)
  }

  func testLabelOriginScalesPadding() {
    let t = iPhone11Transform()
    let font = CTFontCreateWithName("Monaco" as CFString, t.labelFontSize(8), nil)
    let ascent = CTFontGetAscent(font)
    let descent = CTFontGetDescent(font)
    // With padding=8 instead of 4
    let origin = t.labelOrigin(padding: 8, ascent: ascent, descent: descent)
    // overlayScale = 1.0 → x = 8 * 1.0 = 8
    XCTAssertEqual(origin.x, 8.0, accuracy: 0.001)
    // y is still centered within 24px header (padding only affects x)
    let lineHeight = ascent + descent
    let expectedY = (24.0 - lineHeight) / 2 + ascent
    XCTAssertEqual(origin.y, expectedY, accuracy: 0.001)
  }

  func testLabelPositionRelativeToHeaderRect() {
    // Verify the label is centered within the visible header.
    let t = iPhone11Transform()
    let font = CTFontCreateWithName("Monaco" as CFString, t.labelFontSize(8), nil)
    let ascent = CTFontGetAscent(font)
    let descent = CTFontGetDescent(font)
    let origin = t.labelOrigin(padding: 4, ascent: ascent, descent: descent)

    let textTop = origin.y - ascent
    let textBottom = origin.y + descent
    // The visible header is y=0 to y=24 (scaledBorderTop).
    let visibleHeaderHeight: CGFloat = 24.0

    // Text should be vertically centered: gap above == gap below
    let gapAbove = textTop
    let gapBelow = visibleHeaderHeight - textBottom
    XCTAssertEqual(
      gapAbove, gapBelow, accuracy: 0.001,
      "Label should be vertically centered in visible header")
    // Text must be fully within the visible header
    XCTAssertGreaterThanOrEqual(
      textTop, 0,
      "Text top should not extend above the buffer")
    XCTAssertLessThanOrEqual(
      textBottom, visibleHeaderHeight,
      "Text bottom should not extend below the visible header")
  }

  func testLabelFontSize() {
    let t = iPhone11Transform()
    // 8 * overlayScale(1.0) = 8
    XCTAssertEqual(t.labelFontSize(8), 8, accuracy: 0.01)
  }

  // MARK: - No scaling (1x retina, 1.0 scale)

  func testNoScalingPassesThrough() {
    let t = FBOverlayCoordinateTransform(
      screenPixelWidth: 414, screenPixelHeight: 896,
      retinaScale: 1.0, videoScale: 1.0,
      borderTop: 24, scaledBorderTop: 24,
      borderBottom: 0, scaledBorderBottom: 0
    )
    // insetCorrection.y = 24 - 24*1.0 = 0
    let p = t.bufferPoint(x: 164, y: 382)
    XCTAssertEqual(p.x, 164, accuracy: 0.01)
    XCTAssertEqual(p.y, 382, accuracy: 0.01)
  }

  // MARK: - 3x retina

  func testIPhone3xRetina() {
    let t = FBOverlayCoordinateTransform(
      screenPixelWidth: 1170, screenPixelHeight: 2532,
      retinaScale: 3.0, videoScale: 0.5,
      // scaledBorderTop = borderTop * videoScale * retinaScale = 24 * 0.5 * 3.0 = 36
      borderTop: 24, scaledBorderTop: 36,
      borderBottom: 0, scaledBorderBottom: 0
    )
    XCTAssertEqual(t.overlayScale, 1.5, accuracy: 0.01)
    XCTAssertEqual(t.bufferWidth, 585)
    // insetCorrection.y = 36 - 24*1.5 = 0
    let p = t.bufferPoint(x: 200, y: 24)
    XCTAssertEqual(p.x, 300, accuracy: 0.01) // 200 * 1.5
    XCTAssertEqual(p.y, 36, accuracy: 0.01) // 24 * 1.5 + 0 = 36
  }

  // MARK: - Inset correction is zero under correct scaling

  func testInsetCorrectionIsZeroAtAllScales() {
    // After the bugfix, when scaledBorderTop is correctly set to borderTop * videoScale * retinaScale,
    // insetCorrection.y is 0 — overlay shape coords map 1:1 to buffer coords (within the reserved region).
    let cases: [(retina: CGFloat, scale: CGFloat, border: Int)] = [
      (1.0, 1.0, 0),
      (2.0, 0.5, 24),
      (2.0, 1.0, 24),
      (3.0, 0.5, 24),
      (3.0, 0.25, 24),
      (3.0, 1.0, 24),
    ]
    for (retina, scale, border) in cases {
      let scaledBorderTop = Int(CGFloat(border) * scale * retina)
      let t = FBOverlayCoordinateTransform(
        screenPixelWidth: 1000, screenPixelHeight: 2000,
        retinaScale: retina, videoScale: scale,
        borderTop: border, scaledBorderTop: scaledBorderTop,
        borderBottom: 0, scaledBorderBottom: 0
      )
      XCTAssertEqual(
        t.insetCorrection.y, 0, accuracy: 0.001,
        "insetCorrection.y must be 0 at retina=\(retina) scale=\(scale) border=\(border)")
    }
  }

  // MARK: - device coordinate space (opt-in)

  func testComposedCoordSpaceIsTheDefault() {
    // Omitting coordSpace must match the explicit .composed init exactly — guarantees existing
    // callers continue to see today's wire semantics until they opt in.
    let implicit = iPhone11Transform()
    let explicit = FBOverlayCoordinateTransform(
      screenPixelWidth: 828, screenPixelHeight: 1792,
      retinaScale: 2.0, videoScale: 0.5,
      borderTop: 24, scaledBorderTop: 24,
      borderBottom: 0, scaledBorderBottom: 0,
      coordSpace: .composed
    )
    XCTAssertEqual(implicit.insetCorrection.y, explicit.insetCorrection.y, accuracy: 0.001)
    XCTAssertEqual(implicit.bufferHeight, explicit.bufferHeight)
    XCTAssertEqual(implicit.overlayScale, explicit.overlayScale, accuracy: 0.001)
  }

  func testDeviceCoordSpaceInsetCorrection() {
    // In .device mode, insetCorrection.y is the full scaledBorderTop (no subtraction).
    // This is what causes overlay y=0 to land at the top of the device image rather than
    // the top of the composed frame.
    let t = FBOverlayCoordinateTransform(
      screenPixelWidth: 828, screenPixelHeight: 1792,
      retinaScale: 2.0, videoScale: 0.5,
      borderTop: 24, scaledBorderTop: 24,
      borderBottom: 0, scaledBorderBottom: 0,
      coordSpace: .device
    )
    XCTAssertEqual(t.insetCorrection.x, 0, accuracy: 0.001)
    XCTAssertEqual(t.insetCorrection.y, 24, accuracy: 0.001)
  }

  func testDeviceCoordSpaceBufferPoint() {
    let t = FBOverlayCoordinateTransform(
      screenPixelWidth: 828, screenPixelHeight: 1792,
      retinaScale: 2.0, videoScale: 0.5,
      borderTop: 24, scaledBorderTop: 24,
      borderBottom: 0, scaledBorderBottom: 0,
      coordSpace: .device
    )
    // overlayScale = 0.5 * 2.0 = 1.0
    // bufferPoint(0, 0) lands at (0, scaledBorderTop) = (0, 24)
    let origin = t.bufferPoint(x: 0, y: 0)
    XCTAssertEqual(origin.x, 0, accuracy: 0.001)
    XCTAssertEqual(origin.y, 24, accuracy: 0.001)
    // bufferPoint(0, 100) lands at (0, scaledBorderTop + 100 * overlayScale) = (0, 124)
    let downstream = t.bufferPoint(x: 0, y: 100)
    XCTAssertEqual(downstream.x, 0, accuracy: 0.001)
    XCTAssertEqual(downstream.y, 124, accuracy: 0.001)
  }

  func testDeviceCoordSpaceEquivalentToComposedWithPreShift() {
    // The whole point of .device mode: caller sends y=N, sime2e lands it at the same buffer
    // pixel where the .composed caller would have landed y=N+borderTop. Verify across a few
    // (retina, scale, border) combinations using the production scaledBorderTop formula.
    let cases: [(retina: CGFloat, scale: CGFloat, border: Int)] = [
      (2.0, 0.5, 24),
      (2.0, 1.0, 24),
      (3.0, 0.5, 24),
      (3.0, 1.0, 24),
    ]
    let testYs: [CGFloat] = [0, 50, 100, 382]
    for (retina, scale, border) in cases {
      let scaledBorderTop = Int(CGFloat(border) * scale * retina)
      let composed = FBOverlayCoordinateTransform(
        screenPixelWidth: 1000, screenPixelHeight: 2000,
        retinaScale: retina, videoScale: scale,
        borderTop: border, scaledBorderTop: scaledBorderTop,
        borderBottom: 0, scaledBorderBottom: 0,
        coordSpace: .composed
      )
      let device = FBOverlayCoordinateTransform(
        screenPixelWidth: 1000, screenPixelHeight: 2000,
        retinaScale: retina, videoScale: scale,
        borderTop: border, scaledBorderTop: scaledBorderTop,
        borderBottom: 0, scaledBorderBottom: 0,
        coordSpace: .device
      )
      for y in testYs {
        let composedPoint = composed.bufferPoint(x: 17, y: y + CGFloat(border))
        let devicePoint = device.bufferPoint(x: 17, y: y)
        XCTAssertEqual(
          devicePoint.y, composedPoint.y, accuracy: 0.001,
          "device(y=\(y)) must match composed(y=\(y)+borderTop=\(border)) at retina=\(retina) scale=\(scale)")
        XCTAssertEqual(devicePoint.x, composedPoint.x, accuracy: 0.001)
      }
    }
  }

  func testDeviceCoordSpaceLabelOriginIsUnchanged() {
    // Labels are positioned within the visible header explicitly and never apply
    // insetCorrection.y — switching to .device mode must not move the label off-bar.
    let composed = iPhone11Transform()
    let device = FBOverlayCoordinateTransform(
      screenPixelWidth: 828, screenPixelHeight: 1792,
      retinaScale: 2.0, videoScale: 0.5,
      borderTop: 24, scaledBorderTop: 24,
      borderBottom: 0, scaledBorderBottom: 0,
      coordSpace: .device
    )
    let font = CTFontCreateWithName("Monaco" as CFString, composed.labelFontSize(8), nil)
    let ascent = CTFontGetAscent(font)
    let descent = CTFontGetDescent(font)
    let composedOrigin = composed.labelOrigin(padding: 4, ascent: ascent, descent: descent)
    let deviceOrigin = device.labelOrigin(padding: 4, ascent: ascent, descent: descent)
    XCTAssertEqual(composedOrigin.x, deviceOrigin.x, accuracy: 0.001)
    XCTAssertEqual(composedOrigin.y, deviceOrigin.y, accuracy: 0.001)
  }

  // MARK: - Bar layout

  func testBarHeightPositive() {
    let t = iPhone11Transform()
    XCTAssertGreaterThan(t.barHeight(), 0)
  }

  func testBarHeightEvenIsEven() {
    let h = FBOverlayCoordinateTransform.barHeightEven()
    XCTAssertGreaterThan(h, 0)
    XCTAssertEqual(h % 2, 0)
  }

  func testBarYBottomPlusHeightEqualsBufferHeight() {
    let t = iPhone11Transform()
    XCTAssertEqual(t.barY(position: "bottom") + t.barHeight(), CGFloat(t.bufferHeight), accuracy: 0.01)
  }

  func testBarYTopIsZero() {
    let t = iPhone11Transform()
    XCTAssertEqual(t.barY(position: "top"), 0, accuracy: 0.01)
  }

  func testBarDefaultHeightIs24() {
    XCTAssertEqual(FBOverlayCoordinateTransform.defaultBarHeight, 24)
  }

  // MARK: - Bottom inset is included in bufferHeight

  func testBufferHeightIncludesScaledBorderBottom() {
    let withoutBottom = iPhone11Transform()
    let withBottom = iPhone11Transform(borderBottom: 48, scaledBorderBottom: 24)
    XCTAssertEqual(
      withBottom.bufferHeight, withoutBottom.bufferHeight + 24,
      "bufferHeight must extend by the scaled bottom inset so the overlay matches the video frame")
  }

  func testLabelOriginUnchangedByBottomInset() {
    let withoutBottom = iPhone11Transform()
    let withBottom = iPhone11Transform(borderBottom: 48, scaledBorderBottom: 24)
    let font = CTFontCreateWithName("Monaco" as CFString, withoutBottom.labelFontSize(8), nil)
    let ascent = CTFontGetAscent(font)
    let descent = CTFontGetDescent(font)
    let originA = withoutBottom.labelOrigin(padding: 4, ascent: ascent, descent: descent)
    let originB = withBottom.labelOrigin(padding: 4, ascent: ascent, descent: descent)
    XCTAssertEqual(
      originA.y, originB.y, accuracy: 0.001,
      "label Y must not depend on the bottom inset")
  }

  func testBarYBottomInsideBottomInset() {
    let scaledBottom = 24
    let t = iPhone11Transform(borderBottom: 48, scaledBorderBottom: scaledBottom)
    let bottomInsetStart = CGFloat(t.bufferHeight - scaledBottom)
    XCTAssertGreaterThanOrEqual(
      t.barY(position: "bottom"), bottomInsetStart,
      "bar Y should be at or below the start of the reserved bottom region")
    XCTAssertEqual(
      t.barY(position: "bottom") + t.barHeight(), CGFloat(t.bufferHeight),
      accuracy: 0.01, "bar still ends at bufferHeight")
  }

  // MARK: - Shape model decoding

  func testFBOverlayShapeDecodingCircle() throws {
    let json = """
      {"circle": {"x": 50, "y": 100, "radius": 10, "rgba": [64, 64, 64, 0.5], "effect": {"fadeout": {"durationMs": 350}}}}
      """
    // swiftlint:disable:next force_unwrapping
    let shape = try JSONDecoder().decode(FBOverlayShape.self, from: json.data(using: .utf8)!)
    if case .circle(let c) = shape {
      XCTAssertEqual(c.x, 50)
      XCTAssertEqual(c.y, 100)
      XCTAssertEqual(c.radius, 10)
      if case .fadeout(let fade) = c.effect {
        XCTAssertEqual(fade.durationMs, 350)
      } else {
        XCTFail("Expected fadeout effect")
      }
    } else {
      XCTFail("Expected circle shape")
    }
  }

  func testFBOverlayShapeDecodingRectangle() throws {
    let json = """
      {"rectangle": {"x": 0, "y": 0, "width": -1, "height": 24, "rgba": [64, 64, 64, 1]}}
      """
    // swiftlint:disable:next force_unwrapping
    let shape = try JSONDecoder().decode(FBOverlayShape.self, from: json.data(using: .utf8)!)
    if case .rectangle(let r) = shape {
      XCTAssertEqual(r.width, -1)
      XCTAssertEqual(r.height, 24)
      XCTAssertNil(r.effect)
    } else {
      XCTFail("Expected rectangle shape")
    }
  }

  func testFBOverlayShapeDecodingLabel() throws {
    let json = """
      {"label": {"text": "Step: Login", "padding": 4, "font": "Monaco 8"}}
      """
    // swiftlint:disable:next force_unwrapping
    let shape = try JSONDecoder().decode(FBOverlayShape.self, from: json.data(using: .utf8)!)
    if case .label(let l) = shape {
      XCTAssertEqual(l.text, "Step: Login")
      XCTAssertEqual(l.padding, 4)
      XCTAssertEqual(l.font, "Monaco 8")
    } else {
      XCTFail("Expected label shape")
    }
  }

  func testFBOverlayCommandDecoding() throws {
    let json = """
      {"overlays": [
        {"circle": {"x": 50, "y": 100, "radius": 10, "rgba": [64, 64, 64, 0.5]}},
        {"rectangle": {"x": 0, "y": 0, "width": -1, "height": 24, "rgba": [64, 64, 64, 1]}},
        {"label": {"text": "test", "padding": 4, "font": ""}}
      ]}
      """
    // swiftlint:disable:next force_unwrapping
    let command = try JSONDecoder().decode(FBOverlayCommand.self, from: json.data(using: .utf8)!)
    XCTAssertEqual(command.overlays.count, 3)
  }
}
