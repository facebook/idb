/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreVideo
@testable import FBSimulatorControl
import XCTest

class OverlayRendererTests: XCTestCase {
  func testBufferCreatedWithCorrectDimensions() {
    let renderer = FBOverlayRenderer(width: 100, height: 200)
    XCTAssertEqual(CVPixelBufferGetWidth(renderer.buffer), 100)
    XCTAssertEqual(CVPixelBufferGetHeight(renderer.buffer), 200)
  }

  func testBufferInitiallyTransparent() {
    let renderer = FBOverlayRenderer(width: 10, height: 10)
    CVPixelBufferLockBaseAddress(renderer.buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(renderer.buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(renderer.buffer) else {
      XCTFail("No base address")
      return
    }
    let bytes = base.assumingMemoryBound(to: UInt8.self)
    let totalBytes = CVPixelBufferGetBytesPerRow(renderer.buffer) * 10
    for i in 0..<totalBytes {
      XCTAssertEqual(bytes[i], 0, "Byte \(i) should be 0 (transparent)")
    }
  }

  // MARK: - Snapshot Tests (iPhone 11: 414x908)

  private func iPhone11Transform(withHeader: Bool = false) -> FBOverlayCoordinateTransform {
    // scaledBorderTop = borderTop * videoScale * retinaScale = 24 * 0.5 * 2.0 = 24 when set
    FBOverlayCoordinateTransform(
      screenPixelWidth: 828,
      screenPixelHeight: 1792,
      retinaScale: 2.0,
      videoScale: 0.5,
      borderTop: withHeader ? 24 : 0,
      scaledBorderTop: withHeader ? 24 : 0,
      borderBottom: 0,
      scaledBorderBottom: 0
    )
  }

  func testSnapshotCircle() {
    assertOverlaySnapshot(
      .init(
        name: "circle_iphone11", width: 0, height: 0,
        transform: iPhone11Transform(),
        overlays: [.circle(.init(x: 207, y: 454, radius: 20, rgba: [255, 0, 0, 1.0], effect: nil))]
      ))
  }

  func testSnapshotRectangleNegativeWidth() {
    assertOverlaySnapshot(
      .init(
        name: "rect_negative_width_iphone11", width: 0, height: 0,
        transform: iPhone11Transform(),
        overlays: [.rectangle(.init(x: 0, y: 0, width: -1, height: 40, rgba: [64, 64, 64, 1.0], effect: nil))]
      ))
  }

  func testClearResetsBufferToTransparent() {
    let renderer = FBOverlayRenderer(width: 10, height: 10)
    let circle = FBOverlayShape.circle(.init(x: 5, y: 5, radius: 3, rgba: [255, 0, 0, 1.0], effect: nil))
    renderer.render(overlays: [circle])
    renderer.clear()

    CVPixelBufferLockBaseAddress(renderer.buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(renderer.buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(renderer.buffer) else {
      XCTFail("No base address")
      return
    }
    let bytes = base.assumingMemoryBound(to: UInt8.self)
    let totalBytes = CVPixelBufferGetBytesPerRow(renderer.buffer) * 10
    for i in 0..<totalBytes {
      XCTAssertEqual(bytes[i], 0, "Byte \(i) should be 0 after clear")
    }
  }

  func testHasActiveEffectsReturnsTrueForFadeout() {
    let renderer = FBOverlayRenderer(width: 10, height: 10)
    let circle = FBOverlayShape.circle(.init(x: 5, y: 5, radius: 3, rgba: [255, 0, 0, 1.0], effect: .fadeout(.init(durationMs: 5000))))
    renderer.render(overlays: [circle])
    XCTAssertTrue(renderer.hasActiveEffects(), "Should have active effects immediately after render")
  }

  func testHasActiveEffectsReturnsFalseWithNoEffects() {
    let renderer = FBOverlayRenderer(width: 10, height: 10)
    let circle = FBOverlayShape.circle(.init(x: 5, y: 5, radius: 3, rgba: [255, 0, 0, 1.0], effect: nil))
    renderer.render(overlays: [circle])
    XCTAssertFalse(renderer.hasActiveEffects(), "Should not have active effects without an effect")
  }

  // MARK: - Scale Factor Tests

  func testScaleFactorDefaultsToOne() {
    let renderer = FBOverlayRenderer(width: 100, height: 100)
    XCTAssertEqual(renderer.scaleFactor, 1.0)
  }

  func testSnapshotRectangle() {
    assertOverlaySnapshot(
      .init(
        name: "rect_iphone11", width: 0, height: 0,
        transform: iPhone11Transform(),
        overlays: [.rectangle(.init(x: 100, y: 200, width: 80, height: 40, rgba: [0, 255, 0, 1.0], effect: nil))]
      ))
  }

  // MARK: - Font Parsing Tests

  func testParseFontSpecWithNameAndSize() {
    let renderer = FBOverlayRenderer(width: 100, height: 100)
    let (name, size) = renderer.parseFontSpec("Monaco 8")
    XCTAssertEqual(name, "Monaco")
    XCTAssertEqual(size, 8.0)
  }

  func testParseFontSpecWithMultiWordName() {
    let renderer = FBOverlayRenderer(width: 100, height: 100)
    let (name, size) = renderer.parseFontSpec("Helvetica Neue 12")
    XCTAssertEqual(name, "Helvetica Neue")
    XCTAssertEqual(size, 12.0)
  }

  func testParseFontSpecWithNameOnly() {
    let renderer = FBOverlayRenderer(width: 100, height: 100)
    let (name, size) = renderer.parseFontSpec("Monaco")
    XCTAssertEqual(name, "Monaco")
    XCTAssertEqual(size, 8.0)
  }

  func testParseFontSpecEmpty() {
    let renderer = FBOverlayRenderer(width: 100, height: 100)
    let (name, size) = renderer.parseFontSpec("")
    XCTAssertEqual(name, "Monaco")
    XCTAssertEqual(size, 8.0)
  }

  // MARK: - Label Rendering Tests

  func testSnapshotLabelInHeader() {
    // tolerance: 255 allows text rendering differences across macOS versions
    // (glyph shapes vary). The snapshot still catches layout changes like the
    // header background size/position and overall image dimensions.
    assertOverlaySnapshot(
      .init(
        name: "label_in_header_iphone11", width: 0, height: 0,
        transform: iPhone11Transform(withHeader: true),
        overlays: [
          .rectangle(.init(x: 0, y: 0, width: -1, height: 24, rgba: [64, 64, 64, 1.0], effect: nil)),
          .label(.init(text: "device.expect()", padding: 4, font: "Monaco 8")),
        ],
        tolerance: 255
      ))
  }

  // MARK: - Bar Content

  func testBarContentPreservedAcrossRenders() {
    let renderer = FBOverlayRenderer(width: 200, height: 100)
    renderer.setBarContent(.text("stats line"), position: "bottom")
    XCTAssertEqual(renderer.barContent["bottom"], .text("stats line"))
    renderer.render(overlays: [])
    XCTAssertEqual(renderer.barContent["bottom"], .text("stats line"), "bar content should persist across overlay renders")
  }

  func testBarContentDefaultsToHidden() {
    let renderer = FBOverlayRenderer(width: 200, height: 100)
    XCTAssertNil(renderer.barContent["bottom"])
    XCTAssertNil(renderer.barContent["top"])
  }

  func testBarContentTopAndBottomIndependent() {
    let renderer = FBOverlayRenderer(width: 200, height: 100)
    renderer.setBarContent(.text("top text"), position: "top")
    renderer.setBarContent(.text("bottom text"), position: "bottom")
    XCTAssertEqual(renderer.barContent["top"], .text("top text"))
    XCTAssertEqual(renderer.barContent["bottom"], .text("bottom text"))
    renderer.setBarContent(.hidden, position: "top")
    XCTAssertEqual(renderer.barContent["top"], .hidden)
    XCTAssertEqual(renderer.barContent["bottom"], .text("bottom text"))
  }

  func testBarContentStatsMode() {
    let renderer = FBOverlayRenderer(width: 200, height: 100)
    renderer.setBarContent(.stats, position: "bottom")
    XCTAssertEqual(renderer.barContent["bottom"], .stats)
    renderer.setStatsText("fb:1.0/s", position: "bottom")
    XCTAssertEqual(renderer.statsText["bottom"], "fb:1.0/s")
  }

  func testBarContentEmptyTextDrawsBar() {
    let transform = FBOverlayCoordinateTransform(
      screenPixelWidth: 200, screenPixelHeight: 100,
      retinaScale: 1.0, videoScale: 1.0,
      borderTop: 0, scaledBorderTop: 0,
      borderBottom: 0, scaledBorderBottom: 0
    )
    let renderer = FBOverlayRenderer(transform: transform)
    renderer.setBarContent(.text(""), position: "bottom")
    renderer.renderToBuffer()
    let barY = Int(transform.barY(position: "bottom") + transform.barHeight() / 2)
    XCTAssertTrue(
      hasContentAt(x: 10, y: barY, buffer: renderer.buffer),
      "bar background should be drawn for empty text")
  }

  func testBarContentHiddenDrawsNothing() {
    let transform = FBOverlayCoordinateTransform(
      screenPixelWidth: 200, screenPixelHeight: 100,
      retinaScale: 1.0, videoScale: 1.0,
      borderTop: 0, scaledBorderTop: 0,
      borderBottom: 0, scaledBorderBottom: 0
    )
    let renderer = FBOverlayRenderer(transform: transform)
    renderer.setBarContent(.hidden, position: "bottom")
    renderer.renderToBuffer()
    let barY = Int(transform.barY(position: "bottom") + transform.barHeight() / 2)
    XCTAssertFalse(
      hasContentAt(x: 10, y: barY, buffer: renderer.buffer),
      "bar must not be drawn when hidden")
  }

  func testStatsTextOnlyRendersInStatsMode() {
    let renderer = FBOverlayRenderer(width: 200, height: 100)
    renderer.setStatsText("fb:1.0/s", position: "bottom")
    renderer.setBarContent(.text("explicit text"), position: "bottom")
    XCTAssertEqual(renderer.barContent["bottom"], .text("explicit text"))
    XCTAssertEqual(renderer.statsText["bottom"], "fb:1.0/s", "stats text is retained but not displayed")
  }

  func testBarContentTextToStatsTransition() {
    let renderer = FBOverlayRenderer(width: 200, height: 100)
    renderer.setBarContent(.text("diagnostic"), position: "bottom")
    renderer.setStatsText("fb:2.0/s", position: "bottom")
    XCTAssertEqual(renderer.barContent["bottom"], .text("diagnostic"))
    renderer.setBarContent(.stats, position: "bottom")
    XCTAssertEqual(renderer.barContent["bottom"], .stats)
    XCTAssertEqual(renderer.statsText["bottom"], "fb:2.0/s")
  }

  // MARK: - Bar Mode

  /// Sample the alpha channel at a point in the rendered overlay buffer.
  private func alphaAt(x: Int, y: Int, buffer: CVPixelBuffer) -> UInt8 {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return 0 }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    // BGRA buffer with premultiplied-first alpha: byte order is B G R A → in little-endian
    // 32-bit access the alpha is the high byte. Reading via the byte at offset+3 of the pixel
    // gives the alpha component directly for the buffer's BGRA storage.
    let pixel = base.advanced(by: y * bytesPerRow + x * 4).assumingMemoryBound(to: UInt8.self)
    return pixel[3]
  }

  func testBarModeDefaultsToPad() {
    let renderer = FBOverlayRenderer(width: 200, height: 100)
    XCTAssertNil(renderer.barMode["top"])
    XCTAssertNil(renderer.barMode["bottom"])
  }

  func testPadModeBarBackgroundIsOpaque() {
    let renderer = FBOverlayRenderer(width: 200, height: 100)
    renderer.setBarMode(.pad, position: "bottom")
    renderer.setBarContent(.text(""), position: "bottom")
    renderer.renderToBuffer()
    let barY = Int(renderer.transform.barY(position: "bottom") + renderer.transform.barHeight() / 2)
    // Sample x=10 (outside text glyph region) — background only.
    let alpha = alphaAt(x: 10, y: barY, buffer: renderer.buffer)
    XCTAssertEqual(alpha, 255, "pad-mode bar background must be fully opaque")
  }

  func testOverlayModeBarBackgroundIsPartiallyTransparent() {
    let renderer = FBOverlayRenderer(width: 200, height: 100)
    renderer.setBarMode(.overlay, position: "bottom")
    renderer.setBarContent(.text(""), position: "bottom")
    renderer.renderToBuffer()
    let barY = Int(renderer.transform.barY(position: "bottom") + renderer.transform.barHeight() / 2)
    let alpha = alphaAt(x: 10, y: barY, buffer: renderer.buffer)
    XCTAssertGreaterThan(alpha, 0, "overlay-mode bar must still be visible")
    XCTAssertLessThan(alpha, 255, "overlay-mode bar must be partially transparent")
  }

  func testTopAndBottomCanHaveDifferentModes() {
    let renderer = FBOverlayRenderer(width: 200, height: 100)
    renderer.setBarMode(.overlay, position: "top")
    renderer.setBarMode(.pad, position: "bottom")
    renderer.setBarContent(.text(""), position: "top")
    renderer.setBarContent(.text(""), position: "bottom")
    renderer.renderToBuffer()
    let topY = Int(renderer.transform.barY(position: "top") + renderer.transform.barHeight() / 2)
    let bottomY = Int(renderer.transform.barY(position: "bottom") + renderer.transform.barHeight() / 2)
    let topAlpha = alphaAt(x: 10, y: topY, buffer: renderer.buffer)
    let bottomAlpha = alphaAt(x: 10, y: bottomY, buffer: renderer.buffer)
    XCTAssertLessThan(topAlpha, 255, "top in overlay mode is partially transparent")
    XCTAssertEqual(bottomAlpha, 255, "bottom in pad mode is fully opaque")
  }

  // MARK: - Bar Fit (shrink-to-fit text)

  /// Find the rightmost x with non-zero alpha in a given row range — the visual right edge of
  /// rendered text. Useful for asserting that shrunk text doesn't extend past the bar edge.
  private func rightmostContentX(yRange: Range<Int>, buffer: CVPixelBuffer) -> Int {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return -1 }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    let width = CVPixelBufferGetWidth(buffer)
    var maxX = -1
    for y in yRange {
      let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
      for x in (0..<width).reversed() {
        // BGRA premultiplied — non-zero R/G/B indicates glyph content (background is black with
        // zero RGB pre-multiplication; glyphs are white).
        if row[x * 4] > 0 || row[x * 4 + 1] > 0 || row[x * 4 + 2] > 0 {
          if x > maxX { maxX = x }
          break
        }
      }
    }
    return maxX
  }

  func testBarFitDefaultsToFalse() {
    let renderer = FBOverlayRenderer(width: 200, height: 100)
    XCTAssertNil(renderer.barFit["bottom"])
    XCTAssertNil(renderer.barFit["top"])
  }

  func testBarFitFalseLetsTextOverflow() {
    // 600px wide canvas; a very long string at default font size will not fit.
    let renderer = FBOverlayRenderer(width: 600, height: 200)
    renderer.setBarFit(false, position: "bottom")
    renderer.setBarContent(
      .text(String(repeating: "X", count: 200)),
      position: "bottom")
    renderer.renderToBuffer()
    let barY = Int(renderer.transform.barY(position: "bottom"))
    let barHeight = Int(renderer.transform.barHeight())
    // With fit=false the text spans past the canvas width — every column up to the rightmost
    // edge has glyph content.
    let maxX = rightmostContentX(yRange: barY..<(barY + barHeight), buffer: renderer.buffer)
    XCTAssertEqual(maxX, 599, "fit=false: glyphs reach the canvas right edge (overflow into clipping)")
  }

  func testBarFitTrueShrinksTextToFit() {
    let renderer = FBOverlayRenderer(width: 600, height: 200)
    renderer.setBarFit(true, position: "bottom")
    renderer.setBarContent(
      .text(String(repeating: "X", count: 200)),
      position: "bottom")
    renderer.renderToBuffer()
    let barY = Int(renderer.transform.barY(position: "bottom"))
    let barHeight = Int(renderer.transform.barHeight())
    let padding = 4
    let maxX = rightmostContentX(yRange: barY..<(barY + barHeight), buffer: renderer.buffer)
    // With fit=true the rightmost glyph must end at or before width - padding.
    XCTAssertLessThanOrEqual(
      maxX, 600 - padding,
      "fit=true: shrunk text must end within the bar's padded right edge")
    XCTAssertGreaterThan(maxX, 0, "fit=true: text must still be rendered")
  }

  func testBarFitIsPerPositionIndependent() {
    let renderer = FBOverlayRenderer(width: 200, height: 100)
    renderer.setBarFit(true, position: "top")
    renderer.setBarFit(false, position: "bottom")
    XCTAssertEqual(renderer.barFit["top"], true)
    XCTAssertEqual(renderer.barFit["bottom"], false)
  }

  func testBarFitAppliesToStatsContent() {
    // Once a bar is in stats mode, fit=true should also shrink the 1Hz stats text.
    let renderer = FBOverlayRenderer(width: 600, height: 200)
    renderer.setBarFit(true, position: "bottom")
    renderer.setBarContent(.stats, position: "bottom")
    renderer.setStatsText(String(repeating: "S", count: 200), position: "bottom")
    let barY = Int(renderer.transform.barY(position: "bottom"))
    let barHeight = Int(renderer.transform.barHeight())
    let padding = 4
    let maxX = rightmostContentX(yRange: barY..<(barY + barHeight), buffer: renderer.buffer)
    XCTAssertLessThanOrEqual(
      maxX, 600 - padding,
      "stats text should shrink to fit when the bar's fit flag is set")
  }

  // MARK: - Animating Shape Persistence Tests (deterministic clock)

  func testAnimatingShapesPreservedAcrossRenders() {
    var clock: CFTimeInterval = 1000.0
    let renderer = FBOverlayRenderer(width: 100, height: 100)
    renderer.currentTime = { clock }

    // Render a circle with a 5s fadeout — this becomes an animating shape
    let fadeCircle = FBOverlayShape.circle(.init(x: 50, y: 50, radius: 10, rgba: [255, 0, 0, 1.0], effect: .fadeout(.init(durationMs: 5000))))
    renderer.render(overlays: [fadeCircle])

    XCTAssertTrue(
      hasContentAt(x: 50, y: 50, buffer: renderer.buffer),
      "Fadeout circle should be visible immediately after render")

    // Advance 100ms, then render new persistent-only overlays — animating circle should survive
    clock += 0.1
    let rect = FBOverlayShape.rectangle(.init(x: 0, y: 0, width: 20, height: 20, rgba: [0, 255, 0, 1.0], effect: nil))
    renderer.render(overlays: [rect])

    XCTAssertTrue(
      hasContentAt(x: 50, y: 50, buffer: renderer.buffer),
      "Fadeout circle should persist as animating shape after new overlay render")
    XCTAssertTrue(
      hasContentAt(x: 10, y: 10, buffer: renderer.buffer),
      "New persistent rectangle should be visible")
  }

  func testExpiredAnimatingShapesPruned() {
    var clock: CFTimeInterval = 1000.0
    let renderer = FBOverlayRenderer(width: 100, height: 100)
    renderer.currentTime = { clock }

    // Render a circle with 100ms fadeout
    let fadeCircle = FBOverlayShape.circle(.init(x: 50, y: 50, radius: 10, rgba: [255, 0, 0, 1.0], effect: .fadeout(.init(durationMs: 100))))
    renderer.render(overlays: [fadeCircle])

    // Advance past the effect duration
    clock += 0.2

    // Render new overlays — expired animating shape should be pruned
    let rect = FBOverlayShape.rectangle(.init(x: 0, y: 0, width: 20, height: 20, rgba: [0, 255, 0, 1.0], effect: nil))
    renderer.render(overlays: [rect])

    XCTAssertFalse(
      hasContentAt(x: 50, y: 50, buffer: renderer.buffer),
      "Expired fadeout circle should not be visible")
    XCTAssertTrue(
      hasContentAt(x: 10, y: 10, buffer: renderer.buffer),
      "Persistent rectangle should be visible")
  }

  func testClearRemovesAnimatingShapes() {
    var clock: CFTimeInterval = 1000.0
    let renderer = FBOverlayRenderer(width: 100, height: 100)
    renderer.currentTime = { clock }

    let fadeCircle = FBOverlayShape.circle(.init(x: 50, y: 50, radius: 10, rgba: [255, 0, 0, 1.0], effect: .fadeout(.init(durationMs: 5000))))
    renderer.render(overlays: [fadeCircle])
    XCTAssertTrue(renderer.hasActiveEffects(), "Should have active animating effects")

    renderer.clear()
    XCTAssertFalse(renderer.hasActiveEffects(), "Should have no active effects after clear")
    XCTAssertFalse(
      hasContentAt(x: 50, y: 50, buffer: renderer.buffer),
      "Buffer should be transparent after clear")
  }

  func testHasActiveEffectsIncludesAnimatingShapes() {
    var clock: CFTimeInterval = 1000.0
    let renderer = FBOverlayRenderer(width: 100, height: 100)
    renderer.currentTime = { clock }

    let fadeCircle = FBOverlayShape.circle(.init(x: 50, y: 50, radius: 10, rgba: [255, 0, 0, 1.0], effect: .fadeout(.init(durationMs: 5000))))
    renderer.render(overlays: [fadeCircle])

    // Advance 100ms, render persistent-only overlays
    clock += 0.1
    let rect = FBOverlayShape.rectangle(.init(x: 0, y: 0, width: 10, height: 10, rgba: [0, 255, 0, 1.0], effect: nil))
    renderer.render(overlays: [rect])

    XCTAssertTrue(
      renderer.hasActiveEffects(),
      "hasActiveEffects should return true while animating shapes are in-flight")
  }

  // MARK: - Animated Snapshot Tests (clock-cranked)

  func testSnapshotFadeoutCircleStart() {
    var clock: CFTimeInterval = 1000.0
    let renderer = FBOverlayRenderer(transform: iPhone11Transform())
    renderer.currentTime = { clock }

    let circle = FBOverlayShape.circle(.init(x: 207, y: 454, radius: 20, rgba: [255, 0, 0, 1.0], effect: .fadeout(.init(durationMs: 1000))))
    renderer.render(overlays: [circle])

    OverlaySnapshotHelper.assertSnapshot(renderer.buffer, named: "fadeout_circle_start_iphone11")
  }

  func testSnapshotFadeoutCircleMid() {
    var clock: CFTimeInterval = 1000.0
    let renderer = FBOverlayRenderer(transform: iPhone11Transform())
    renderer.currentTime = { clock }

    let circle = FBOverlayShape.circle(.init(x: 207, y: 454, radius: 20, rgba: [255, 0, 0, 1.0], effect: .fadeout(.init(durationMs: 1000))))
    renderer.render(overlays: [circle])

    // Advance to 50% through the fadeout
    clock += 0.5
    renderer.renderToBuffer()

    OverlaySnapshotHelper.assertSnapshot(renderer.buffer, named: "fadeout_circle_mid_iphone11")
  }

  func testSnapshotFadeoutCircleEnd() {
    var clock: CFTimeInterval = 1000.0
    let renderer = FBOverlayRenderer(transform: iPhone11Transform())
    renderer.currentTime = { clock }

    let circle = FBOverlayShape.circle(.init(x: 207, y: 454, radius: 20, rgba: [255, 0, 0, 1.0], effect: .fadeout(.init(durationMs: 1000))))
    renderer.render(overlays: [circle])

    // Advance to 99% through the fadeout
    clock += 0.99
    renderer.renderToBuffer()

    OverlaySnapshotHelper.assertSnapshot(renderer.buffer, named: "fadeout_circle_end_iphone11")
  }

  func testSnapshotTransientPersistence() {
    var clock: CFTimeInterval = 1000.0
    let renderer = FBOverlayRenderer(transform: iPhone11Transform())
    renderer.currentTime = { clock }

    // Render a fading circle
    let circle = FBOverlayShape.circle(.init(x: 207, y: 454, radius: 20, rgba: [255, 0, 0, 1.0], effect: .fadeout(.init(durationMs: 1000))))
    renderer.render(overlays: [circle])

    // Advance to 50%, then render a persistent rectangle — circle should survive
    clock += 0.5
    let rect = FBOverlayShape.rectangle(.init(x: 100, y: 200, width: 80, height: 40, rgba: [0, 255, 0, 1.0], effect: nil))
    renderer.render(overlays: [rect])

    OverlaySnapshotHelper.assertSnapshot(renderer.buffer, named: "transient_persistence_iphone11")
  }

  // MARK: - Pixel Helpers

  private func hasContentAt(x: Int, y: Int, buffer: CVPixelBuffer) -> Bool {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return false }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    let pixel = base.advanced(by: y * bytesPerRow + x * 4).assumingMemoryBound(to: UInt8.self)
    return pixel[0] != 0 || pixel[1] != 0 || pixel[2] != 0 || pixel[3] != 0
  }
}
