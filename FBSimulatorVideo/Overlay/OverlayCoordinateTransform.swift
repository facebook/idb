/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import CoreText
import FBSimulatorControl

/// Coordinate space of overlay shape `y` values.
///
/// - `composed`: y=0 is the top of the composed frame, i.e. the top of any reserved header bar
///   (`scaledBorderTop`); callers pre-shift shapes by the header height. The default.
/// - `device`: y=0 is the top of the device image, below any header; the transform adds `scaledBorderTop`.
public enum OverlayCoordSpace: String {
  case composed
  case device
}

/// Maps overlay shape coordinates to overlay buffer pixel coordinates.
public struct OverlayCoordinateTransform {
  public let bufferWidth: Int
  public let bufferHeight: Int

  /// Scale factor mapping shape coordinates to buffer pixels.
  /// Equal to `videoScale * retinaScale`.
  public let overlayScale: CGFloat

  /// Correction applied to shape coordinates after scaling. Driven by `coordSpace`:
  /// see `OverlayCoordSpace`.
  public let insetCorrection: CGPoint

  /// Visible header height in buffer pixels (the `scaledBorderTop` init parameter).
  let headerHeight: CGFloat
  /// The screen this transform lays overlays out on, in pixels as the interface shows it.
  let screenPixelWidth: Int
  let screenPixelHeight: Int
  /// The screen area of the canvas the screen is shown in, in pixels. It differs from the screen when a recording
  /// letterboxes a screen of another shape into the canvas it started with.
  let canvasPixelWidth: Int
  let canvasPixelHeight: Int
  /// Map shape coordinates into the screen as the canvas shows it, scaled to fit and centred. Bars and the header
  /// label span the canvas, so they keep `overlayScale`.
  private let shapeScale: CGFloat
  private let shapeCorrection: CGPoint
  /// Where the screen sits within the canvas, in buffer pixels: zero unless the screen is letterboxed.
  private let letterboxOffset: CGPoint
  private let retinaScale: CGFloat
  private let videoScale: CGFloat
  private let borders: (top: Int, scaledTop: Int, bottom: Int, scaledBottom: Int)
  private let coordSpace: OverlayCoordSpace

  public init(
    screenPixelWidth: Int,
    screenPixelHeight: Int,
    retinaScale: CGFloat,
    videoScale: CGFloat,
    borderTop: Int,
    scaledBorderTop: Int,
    borderBottom: Int,
    scaledBorderBottom: Int,
    coordSpace: OverlayCoordSpace = .composed,
    canvasPixelWidth: Int? = nil,
    canvasPixelHeight: Int? = nil
  ) {
    let canvasPixelWidth = canvasPixelWidth ?? screenPixelWidth
    let canvasPixelHeight = canvasPixelHeight ?? screenPixelHeight
    self.screenPixelWidth = screenPixelWidth
    self.screenPixelHeight = screenPixelHeight
    self.canvasPixelWidth = canvasPixelWidth
    self.canvasPixelHeight = canvasPixelHeight
    self.retinaScale = retinaScale
    self.videoScale = videoScale
    self.borders = (borderTop, scaledBorderTop, borderBottom, scaledBorderBottom)
    self.coordSpace = coordSpace
    self.bufferWidth = Int(Double(canvasPixelWidth) * Double(videoScale))
    // Must include both scaled insets so the overlay buffer matches the video frame; a shorter overlay is
    // shifted down by the compositor.
    self.bufferHeight =
      Int(Double(canvasPixelHeight) * Double(videoScale)) + scaledBorderTop + scaledBorderBottom
    self.overlayScale = videoScale * retinaScale
    self.headerHeight = CGFloat(scaledBorderTop)
    switch coordSpace {
    case .composed:
      self.insetCorrection = CGPoint(
        x: 0,
        y: CGFloat(scaledBorderTop) - CGFloat(borderTop) * videoScale * retinaScale
      )
    case .device:
      self.insetCorrection = CGPoint(x: 0, y: CGFloat(scaledBorderTop))
    }
    let fit =
      screenPixelWidth > 0 && screenPixelHeight > 0
      ? min(CGFloat(canvasPixelWidth) / CGFloat(screenPixelWidth), CGFloat(canvasPixelHeight) / CGFloat(screenPixelHeight)) : 1
    self.shapeScale = overlayScale * fit
    // A composed-space shape is pre-shifted by the unscaled header, which has to come off before the shape is fitted.
    let headerShift = coordSpace == .composed ? CGFloat(borderTop) * (overlayScale - shapeScale) : 0
    self.letterboxOffset = CGPoint(
      x: (CGFloat(canvasPixelWidth) - CGFloat(screenPixelWidth) * fit) * videoScale / 2,
      y: (CGFloat(canvasPixelHeight) - CGFloat(screenPixelHeight) * fit) * videoScale / 2)
    self.shapeCorrection = CGPoint(x: insetCorrection.x + letterboxOffset.x, y: insetCorrection.y + headerShift + letterboxOffset.y)
  }

  /// The same transform for a screen of another size shown in a canvas of this size, as after a rotation or a
  /// switch to another display.
  func resized(screenPixelWidth: Int, screenPixelHeight: Int, canvasPixelWidth: Int, canvasPixelHeight: Int) -> OverlayCoordinateTransform {
    OverlayCoordinateTransform(
      screenPixelWidth: screenPixelWidth, screenPixelHeight: screenPixelHeight, retinaScale: retinaScale, videoScale: videoScale,
      borderTop: borders.top, scaledBorderTop: borders.scaledTop, borderBottom: borders.bottom, scaledBorderBottom: borders.scaledBottom,
      coordSpace: coordSpace, canvasPixelWidth: canvasPixelWidth, canvasPixelHeight: canvasPixelHeight)
  }

  func bufferPoint(x: CGFloat, y: CGFloat) -> CGPoint {
    CGPoint(
      x: x * shapeScale + shapeCorrection.x,
      y: y * shapeScale + shapeCorrection.y
    )
  }

  public func bufferSize(width: CGFloat, height: CGFloat) -> CGSize {
    CGSize(width: width * shapeScale, height: height * shapeScale)
  }

  func bufferRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
    let bx = x * shapeScale + shapeCorrection.x
    let by = y * shapeScale + shapeCorrection.y
    var bw = width < 0 ? width : width * shapeScale
    var bh = height < 0 ? height : height * shapeScale
    if bw < 0 { bw = CGFloat(bufferWidth) - letterboxOffset.x + bw - bx }
    if bh < 0 { bh = CGFloat(bufferHeight) - letterboxOffset.y + bh - by }
    return CGRect(x: bx, y: by, width: bw, height: bh)
  }

  func translateTarget(x: CGFloat, y: CGFloat) -> CGPoint {
    CGPoint(
      x: x * shapeScale + shapeCorrection.x,
      y: y * shapeScale + shapeCorrection.y
    )
  }

  /// Label origin in buffer pixels, vertically centered within the visible header.
  /// The visible header spans y=0 to y=headerHeight in buffer coordinates,
  /// so no `insetCorrection.y` is applied (unlike shapes positioned via `bufferRect`).
  func labelOrigin(padding: CGFloat, ascent: CGFloat, descent: CGFloat) -> CGPoint {
    let scaledPadding = padding * overlayScale
    let lineHeight = ascent + descent
    let centeredY: CGFloat
    if headerHeight > 0 {
      centeredY = (headerHeight - lineHeight) / 2 + ascent
    } else {
      centeredY = scaledPadding + ascent
    }
    return CGPoint(
      x: scaledPadding + insetCorrection.x,
      y: centeredY
    )
  }

  /// Scale a label font size to buffer pixels.
  func labelFontSize(_ baseFontSize: CGFloat) -> CGFloat {
    baseFontSize * overlayScale
  }

  // MARK: - Bars

  /// Default bar height in logical pixels.
  public static let defaultBarHeight: Int = 24

  /// Bar font size in buffer pixels, derived from the bar's logical height.
  func barFontSize() -> CGFloat {
    let logicalHeight = CGFloat(Self.defaultBarHeight)
    let padding: CGFloat = 4
    return (logicalHeight - padding * 2) * overlayScale
  }

  /// Bar height in buffer pixels.
  func barHeight() -> CGFloat {
    CGFloat(Self.defaultBarHeight) * overlayScale
  }

  /// Bar height in logical pixels, rounded to even for H.264/NV12 compatibility.
  public static func barHeightEven(logicalHeight: Int = defaultBarHeight) -> Int {
    logicalHeight % 2 == 0 ? logicalHeight : logicalHeight + 1
  }

  /// Bar Y position in buffer pixels for a given position.
  func barY(position: String) -> CGFloat {
    switch position {
    case "top":
      return 0
    case "bottom":
      return CGFloat(bufferHeight) - barHeight()
    default:
      return 0
    }
  }
}
