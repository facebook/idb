/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreText
@testable import FBSimulatorControl
@testable import FBSimulatorVideo
import Foundation
import Testing

/// Fixture reference: iPhone 11
///   - Screen: 828×1792 pixels, 414×896 points, 2x retina
///   - With --border-top 24 at videoScale=0.5:
///     - scaledBorderTop = 24 * videoScale * retinaScale = 24 * 0.5 * 2.0 = 24 buffer px
///     - buffer = 414×(896 + 24) = 414×920
///     - overlayScale = 0.5 * 2.0 = 1.0
///     - insetCorrection.y = scaledBorderTop - borderTop * overlayScale = 24 - 24 = 0
@Suite
struct OverlayCoordinateTransformTests {

  private func iPhone11Transform(borderBottom: Int = 0, scaledBorderBottom: Int = 0) -> OverlayCoordinateTransform {
    OverlayCoordinateTransform(
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

  @Test
  func bufferDimensions() {
    let t = iPhone11Transform()
    #expect(t.bufferWidth == 414)
    // 1792 * 0.5 + 24 (scaledBorderTop) = 920
    #expect(t.bufferHeight == 920)
  }

  @Test
  func overlayScale() {
    let t = iPhone11Transform()
    #expect(abs(t.overlayScale - 1.0) <= 0.01)
  }

  @Test
  func insetCorrection() {
    let t = iPhone11Transform()
    // scaledBorderTop(24) - borderTop(24) * overlayScale(1.0) = 0
    #expect(abs(t.insetCorrection.x - 0) <= 0.01)
    #expect(abs(t.insetCorrection.y - 0) <= 0.01)
  }

  // MARK: - Point mapping

  @Test
  func bufferPointForClickAtCenter() {
    let t = iPhone11Transform()
    let p = t.bufferPoint(x: 164, y: 382)
    #expect(abs(p.x - 164) <= 0.01)
    #expect(abs(p.y - 382) <= 0.01)
  }

  // MARK: - Size mapping

  @Test
  func bufferSizeAtScale1() {
    let t = iPhone11Transform()
    let s = t.bufferSize(width: 44, height: 48)
    #expect(abs(s.width - 44) <= 0.01)
    #expect(abs(s.height - 48) <= 0.01)
  }

  // MARK: - Rect

  @Test
  func bufferRectNegativeWidthSpansToEdge() {
    let t = iPhone11Transform()
    let r = t.bufferRect(x: 0, y: 24, width: -1, height: 10)
    #expect(abs(r.origin.x - 0) <= 0.01)
    #expect(abs(r.origin.y - 24) <= 0.01)
    #expect(abs(r.size.width - 414) <= 1)
    #expect(abs(r.size.height - 10) <= 0.01)
  }

  @Test
  func bufferRectPositive() {
    let t = iPhone11Transform()
    let r = t.bufferRect(x: 10, y: 34, width: 100, height: 50)
    #expect(abs(r.origin.x - 10) <= 0.01)
    #expect(abs(r.origin.y - 34) <= 0.01)
    #expect(abs(r.size.width - 100) <= 0.01)
    #expect(abs(r.size.height - 50) <= 0.01)
  }

  // MARK: - Translate target

  @Test
  func translateTarget() {
    let t = iPhone11Transform()
    let p = t.translateTarget(x: 200, y: 500)
    #expect(abs(p.x - 200) <= 0.01)
    #expect(abs(p.y - 500) <= 0.01)
  }

  // MARK: - Label layout

  @Test
  func labelOriginIPhone11() {
    let t = iPhone11Transform()
    let font = CTFontCreateWithName("Monaco" as CFString, t.labelFontSize(8), nil)
    let ascent = CTFontGetAscent(font)
    let descent = CTFontGetDescent(font)
    let origin = t.labelOrigin(padding: 4, ascent: ascent, descent: descent)
    let lineHeight = ascent + descent
    #expect(abs(origin.x - 4.0) <= 0.001)
    // y = centered within visible 24px header, no insetCorrection.y
    let expectedY = (24.0 - lineHeight) / 2 + ascent
    #expect(abs(origin.y - expectedY) <= 0.001)
  }

  @Test
  func labelOriginDoesNotApplyInsetCorrection() {
    // Even when insetCorrection.y is nonzero, labelOrigin doesn't apply it. The label
    // centers within the visible header (= scaledBorderTop), not at logical y=0.
    let t = OverlayCoordinateTransform(
      screenPixelWidth: 828, screenPixelHeight: 1792,
      retinaScale: 2.0, videoScale: 0.5,
      borderTop: 24, scaledBorderTop: 12, // intentionally underprovisioned to force insetCorrection.y != 0
      borderBottom: 0, scaledBorderBottom: 0
    )
    #expect(abs(t.insetCorrection.y - -12) <= 0.01)
    let font = CTFontCreateWithName("Monaco" as CFString, t.labelFontSize(8), nil)
    let ascent = CTFontGetAscent(font)
    let descent = CTFontGetDescent(font)
    let origin = t.labelOrigin(padding: 4, ascent: ascent, descent: descent)
    let lineHeight = ascent + descent
    let expectedY = (12.0 - lineHeight) / 2 + ascent
    #expect(abs(origin.y - expectedY) <= 0.001)
  }

  @Test
  func labelOrigin3xRetina() {
    let t = OverlayCoordinateTransform(
      screenPixelWidth: 1170, screenPixelHeight: 2532,
      retinaScale: 3.0, videoScale: 0.5,
      // scaledBorderTop = borderTop * videoScale * retinaScale = 24 * 0.5 * 3.0 = 36
      borderTop: 24, scaledBorderTop: 36,
      borderBottom: 0, scaledBorderBottom: 0
    )
    // overlayScale = 1.5, headerHeight = 36
    #expect(abs(t.overlayScale - 1.5) <= 0.001)
    let font = CTFontCreateWithName("Monaco" as CFString, t.labelFontSize(8), nil)
    let ascent = CTFontGetAscent(font)
    let descent = CTFontGetDescent(font)
    let origin = t.labelOrigin(padding: 4, ascent: ascent, descent: descent)
    let lineHeight = ascent + descent
    // x = 4 * 1.5 = 6
    #expect(abs(origin.x - 6.0) <= 0.001)
    // y = centered within visible 36px header
    let expectedY = (36.0 - lineHeight) / 2 + ascent
    #expect(abs(origin.y - expectedY) <= 0.001)
  }

  @Test
  func labelOriginZeroBorderTop() {
    let t = OverlayCoordinateTransform(
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
    #expect(abs(origin.x - 4.0) <= 0.001)
    #expect(abs(origin.y - (4.0 + ascent)) <= 0.001)
  }

  @Test
  func labelFontSize() {
    let t = iPhone11Transform()
    #expect(abs(t.labelFontSize(8) - 8) <= 0.01)
  }

  // MARK: - 3x retina

  @Test
  func iPhone3xRetina() {
    let t = OverlayCoordinateTransform(
      screenPixelWidth: 1170, screenPixelHeight: 2532,
      retinaScale: 3.0, videoScale: 0.5,
      // scaledBorderTop = borderTop * videoScale * retinaScale = 24 * 0.5 * 3.0 = 36
      borderTop: 24, scaledBorderTop: 36,
      borderBottom: 0, scaledBorderBottom: 0
    )
    #expect(abs(t.overlayScale - 1.5) <= 0.01)
    #expect(t.bufferWidth == 585)
    // insetCorrection.y = 36 - 24*1.5 = 0
    let p = t.bufferPoint(x: 200, y: 24)
    #expect(abs(p.x - 300) <= 0.01) // 200 * 1.5
    #expect(abs(p.y - 36) <= 0.01) // 24 * 1.5 + 0 = 36
  }

  // MARK: - Inset correction is zero under correct scaling

  @Test
  func insetCorrectionIsZeroAtAllScales() {
    // When scaledBorderTop is borderTop * videoScale * retinaScale, insetCorrection.y is 0 —
    // overlay shape coords map 1:1 to buffer coords (within the reserved region).
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
      let t = OverlayCoordinateTransform(
        screenPixelWidth: 1000, screenPixelHeight: 2000,
        retinaScale: retina, videoScale: scale,
        borderTop: border, scaledBorderTop: scaledBorderTop,
        borderBottom: 0, scaledBorderBottom: 0
      )
      #expect(abs(t.insetCorrection.y - 0) <= 0.001, "insetCorrection.y must be 0 at retina=\(retina) scale=\(scale) border=\(border)")
    }
  }

  // MARK: - device coordinate space (opt-in)

  @Test
  func composedCoordSpaceIsTheDefault() {
    // Omitting `coordSpace` must be identical to passing `.composed`.
    let implicit = iPhone11Transform()
    let explicit = OverlayCoordinateTransform(
      screenPixelWidth: 828, screenPixelHeight: 1792,
      retinaScale: 2.0, videoScale: 0.5,
      borderTop: 24, scaledBorderTop: 24,
      borderBottom: 0, scaledBorderBottom: 0,
      coordSpace: .composed
    )
    #expect(abs(implicit.insetCorrection.y - explicit.insetCorrection.y) <= 0.001)
    #expect(implicit.bufferHeight == explicit.bufferHeight)
    #expect(abs(implicit.overlayScale - explicit.overlayScale) <= 0.001)
  }

  @Test
  func deviceCoordSpaceInsetCorrection() {
    // In .device mode, insetCorrection.y is the full scaledBorderTop (no subtraction).
    // This is what causes overlay y=0 to land at the top of the device image rather than
    // the top of the composed frame.
    let t = OverlayCoordinateTransform(
      screenPixelWidth: 828, screenPixelHeight: 1792,
      retinaScale: 2.0, videoScale: 0.5,
      borderTop: 24, scaledBorderTop: 24,
      borderBottom: 0, scaledBorderBottom: 0,
      coordSpace: .device
    )
    #expect(abs(t.insetCorrection.x - 0) <= 0.001)
    #expect(abs(t.insetCorrection.y - 24) <= 0.001)
  }

  @Test
  func deviceCoordSpaceBufferPoint() {
    let t = OverlayCoordinateTransform(
      screenPixelWidth: 828, screenPixelHeight: 1792,
      retinaScale: 2.0, videoScale: 0.5,
      borderTop: 24, scaledBorderTop: 24,
      borderBottom: 0, scaledBorderBottom: 0,
      coordSpace: .device
    )
    // overlayScale = 0.5 * 2.0 = 1.0
    // bufferPoint(0, 0) lands at (0, scaledBorderTop) = (0, 24)
    let origin = t.bufferPoint(x: 0, y: 0)
    #expect(abs(origin.x - 0) <= 0.001)
    #expect(abs(origin.y - 24) <= 0.001)
    // bufferPoint(0, 100) lands at (0, scaledBorderTop + 100 * overlayScale) = (0, 124)
    let downstream = t.bufferPoint(x: 0, y: 100)
    #expect(abs(downstream.x - 0) <= 0.001)
    #expect(abs(downstream.y - 124) <= 0.001)
  }

  @Test
  func deviceCoordSpaceEquivalentToComposedWithPreShift() {
    // In `.device` mode y=N lands on the buffer pixel that `.composed` y=N+borderTop lands on,
    // across (retina, scale, border) using the production scaledBorderTop formula.
    let cases: [(retina: CGFloat, scale: CGFloat, border: Int)] = [
      (2.0, 0.5, 24),
      (2.0, 1.0, 24),
      (3.0, 0.5, 24),
      (3.0, 1.0, 24),
    ]
    let testYs: [CGFloat] = [0, 50, 100, 382]
    for (retina, scale, border) in cases {
      let scaledBorderTop = Int(CGFloat(border) * scale * retina)
      let composed = OverlayCoordinateTransform(
        screenPixelWidth: 1000, screenPixelHeight: 2000,
        retinaScale: retina, videoScale: scale,
        borderTop: border, scaledBorderTop: scaledBorderTop,
        borderBottom: 0, scaledBorderBottom: 0,
        coordSpace: .composed
      )
      let device = OverlayCoordinateTransform(
        screenPixelWidth: 1000, screenPixelHeight: 2000,
        retinaScale: retina, videoScale: scale,
        borderTop: border, scaledBorderTop: scaledBorderTop,
        borderBottom: 0, scaledBorderBottom: 0,
        coordSpace: .device
      )
      for y in testYs {
        let composedPoint = composed.bufferPoint(x: 17, y: y + CGFloat(border))
        let devicePoint = device.bufferPoint(x: 17, y: y)
        #expect(abs(devicePoint.y - composedPoint.y) <= 0.001, "device(y=\(y)) must match composed(y=\(y)+borderTop=\(border)) at retina=\(retina) scale=\(scale)")
        #expect(abs(devicePoint.x - composedPoint.x) <= 0.001)
      }
    }
  }

  @Test
  func deviceCoordSpaceLabelOriginIsUnchanged() {
    // Labels are positioned within the visible header explicitly and never apply
    // insetCorrection.y — switching to .device mode must not move the label off-bar.
    let composed = iPhone11Transform()
    let device = OverlayCoordinateTransform(
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
    #expect(abs(composedOrigin.x - deviceOrigin.x) <= 0.001)
    #expect(abs(composedOrigin.y - deviceOrigin.y) <= 0.001)
  }

  // MARK: - Bar layout

  @Test
  func barHeightEvenIsEven() {
    let h = OverlayCoordinateTransform.barHeightEven()
    #expect(h > 0)
    #expect(h % 2 == 0)
  }

  @Test
  func barYBottomPlusHeightEqualsBufferHeight() {
    let t = iPhone11Transform()
    #expect(abs(t.barY(position: "bottom") + t.barHeight() - CGFloat(t.bufferHeight)) <= 0.01)
  }

  @Test
  func barYTopIsZero() {
    let t = iPhone11Transform()
    #expect(abs(t.barY(position: "top") - 0) <= 0.01)
  }

  // MARK: - Bottom inset is included in bufferHeight

  @Test
  func bufferHeightIncludesScaledBorderBottom() {
    let withoutBottom = iPhone11Transform()
    let withBottom = iPhone11Transform(borderBottom: 48, scaledBorderBottom: 24)
    #expect(withBottom.bufferHeight == withoutBottom.bufferHeight + 24, "bufferHeight must extend by the scaled bottom inset so the overlay matches the video frame")
  }

  @Test
  func labelOriginUnchangedByBottomInset() {
    let withoutBottom = iPhone11Transform()
    let withBottom = iPhone11Transform(borderBottom: 48, scaledBorderBottom: 24)
    let font = CTFontCreateWithName("Monaco" as CFString, withoutBottom.labelFontSize(8), nil)
    let ascent = CTFontGetAscent(font)
    let descent = CTFontGetDescent(font)
    let originA = withoutBottom.labelOrigin(padding: 4, ascent: ascent, descent: descent)
    let originB = withBottom.labelOrigin(padding: 4, ascent: ascent, descent: descent)
    #expect(abs(originA.y - originB.y) <= 0.001, "label Y must not depend on the bottom inset")
  }

  @Test
  func barYBottomInsideBottomInset() {
    let scaledBottom = 24
    let t = iPhone11Transform(borderBottom: 48, scaledBorderBottom: scaledBottom)
    let bottomInsetStart = CGFloat(t.bufferHeight - scaledBottom)
    #expect(t.barY(position: "bottom") >= bottomInsetStart, "bar Y should be at or below the start of the reserved bottom region")
    #expect(abs(t.barY(position: "bottom") + t.barHeight() - CGFloat(t.bufferHeight)) <= 0.01, "bar still ends at bufferHeight")
  }

  // MARK: - Shape model decoding

  @Test
  func fbOverlayShapeDecodingCircle() throws {
    let json = """
      {"circle": {"x": 50, "y": 100, "radius": 10, "rgba": [64, 64, 64, 0.5], "effect": {"fadeout": {"durationMs": 350}}}}
      """
    // swiftlint:disable:next force_unwrapping
    let shape = try JSONDecoder().decode(OverlayShape.self, from: json.data(using: .utf8)!)
    if case .circle(let c) = shape {
      #expect(c.x == 50)
      #expect(c.y == 100)
      #expect(c.radius == 10)
      if case .fadeout(let fade) = c.effect {
        #expect(fade.durationMs == 350)
      } else {
        Issue.record("Expected fadeout effect")
      }
    } else {
      Issue.record("Expected circle shape")
    }
  }

  @Test
  func fbOverlayShapeDecodingRectangle() throws {
    let json = """
      {"rectangle": {"x": 0, "y": 0, "width": -1, "height": 24, "rgba": [64, 64, 64, 1]}}
      """
    // swiftlint:disable:next force_unwrapping
    let shape = try JSONDecoder().decode(OverlayShape.self, from: json.data(using: .utf8)!)
    if case .rectangle(let r) = shape {
      #expect(r.width == -1)
      #expect(r.height == 24)
      #expect(r.effect == nil)
    } else {
      Issue.record("Expected rectangle shape")
    }
  }

  @Test
  func fbOverlayShapeDecodingLabel() throws {
    let json = """
      {"label": {"text": "Step: Login", "padding": 4, "font": "Monaco 8"}}
      """
    // swiftlint:disable:next force_unwrapping
    let shape = try JSONDecoder().decode(OverlayShape.self, from: json.data(using: .utf8)!)
    if case .label(let l) = shape {
      #expect(l.text == "Step: Login")
      #expect(l.padding == 4)
      #expect(l.font == "Monaco 8")
    } else {
      Issue.record("Expected label shape")
    }
  }

  @Test
  func fbOverlayCommandDecoding() throws {
    let json = """
      {"overlays": [
        {"circle": {"x": 50, "y": 100, "radius": 10, "rgba": [64, 64, 64, 0.5]}},
        {"rectangle": {"x": 0, "y": 0, "width": -1, "height": 24, "rgba": [64, 64, 64, 1]}},
        {"label": {"text": "test", "padding": 4, "font": ""}}
      ]}
      """
    // swiftlint:disable:next force_unwrapping
    let command = try JSONDecoder().decode(OverlayCommand.self, from: json.data(using: .utf8)!)
    #expect(command.overlays.count == 3)
  }
}
