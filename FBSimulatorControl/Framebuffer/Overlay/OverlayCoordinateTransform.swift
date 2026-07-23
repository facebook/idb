/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import CoreText

/// Coordinate space callers use when sending overlay shape `y` values to sime2e.
///
/// - `composed`: y=0 is the top of the composed video frame — the top of the reserved
///   header bar (`scaledBorderTop`) when one is present. Callers must pre-shift their
///   shapes by the header height to land in the device-image region. This is the
///   historical contract and the default for backward compatibility.
/// - `device`: y=0 is the top of the device image (i.e. *below* any reserved header).
///   The transform adds `scaledBorderTop` internally so callers can send raw
///   device-frame coordinates without knowing about the header bar's geometry.
public enum FBOverlayCoordSpace: String {
  case composed
  case device
}

/// Encapsulates all coordinate math for mapping jest_e2e overlay JSON
/// coordinates to overlay buffer pixel coordinates.
///
/// The transform supports two coordinate spaces (`FBOverlayCoordSpace`):
/// - `.composed` (default): historical semantics — `insetCorrection.y` is zero (or near
///   zero modulo integer truncation) so overlay y is taken at face value in buffer space.
/// - `.device`: `insetCorrection.y == scaledBorderTop` so overlay y=0 lands at the top
///   of the device image and shape geometry no longer needs to know about the header.
public struct FBOverlayCoordinateTransform {
  public let bufferWidth: Int
  public let bufferHeight: Int

  /// Scale factor mapping shape coordinates to buffer pixels.
  /// Equal to `videoScale * retinaScale`.
  public let overlayScale: CGFloat

  /// Correction applied to shape coordinates after scaling. Driven by `coordSpace`:
  /// see `FBOverlayCoordSpace`.
  public let insetCorrection: CGPoint

  /// Visible header height in buffer pixels (the `scaledBorderTop` init parameter).
  public let headerHeight: CGFloat

  public init(
    screenPixelWidth: Int,
    screenPixelHeight: Int,
    retinaScale: CGFloat,
    videoScale: CGFloat,
    borderTop: Int,
    scaledBorderTop: Int,
    borderBottom: Int,
    scaledBorderBottom: Int,
    coordSpace: FBOverlayCoordSpace = .composed
  ) {
    self.bufferWidth = Int(Double(screenPixelWidth) * Double(videoScale))
    // bufferHeight must include BOTH the top and bottom scaled insets so the overlay buffer
    // matches the dimensions of the video frame produced by FBSimulatorVideoStream. If the
    // bottom inset is omitted here the overlay ends up shorter than the frame, and the
    // compositor shifts the overlay downward by the missing amount — which silently pushes
    // any top-positioned content (e.g. header textboxes) below where it was placed.
    self.bufferHeight =
      Int(Double(screenPixelHeight) * Double(videoScale)) + scaledBorderTop + scaledBorderBottom
    self.overlayScale = videoScale * retinaScale
    self.headerHeight = CGFloat(scaledBorderTop)
    switch coordSpace {
    case .composed:
      self.insetCorrection = CGPoint(
        x: 0,
        y: CGFloat(scaledBorderTop) - CGFloat(borderTop) * videoScale * retinaScale
      )
    case .device:
      // In device-frame mode, overlay y=0 maps to the top of the device image, which sits
      // immediately below the reserved header. The shift is the full scaledBorderTop, with
      // no `borderTop * overlayScale` subtraction — callers send unshifted device coords.
      self.insetCorrection = CGPoint(x: 0, y: CGFloat(scaledBorderTop))
    }
  }

  public func bufferPoint(x: CGFloat, y: CGFloat) -> CGPoint {
    CGPoint(
      x: x * overlayScale + insetCorrection.x,
      y: y * overlayScale + insetCorrection.y
    )
  }

  public func bufferSize(width: CGFloat, height: CGFloat) -> CGSize {
    CGSize(width: width * overlayScale, height: height * overlayScale)
  }

  public func bufferRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
    let bx = x * overlayScale + insetCorrection.x
    let by = y * overlayScale + insetCorrection.y
    var bw = width < 0 ? width : width * overlayScale
    var bh = height < 0 ? height : height * overlayScale
    if bw < 0 { bw = CGFloat(bufferWidth) + bw - bx }
    if bh < 0 { bh = CGFloat(bufferHeight) + bh - by }
    return CGRect(x: bx, y: by, width: bw, height: bh)
  }

  public func translateTarget(x: CGFloat, y: CGFloat) -> CGPoint {
    CGPoint(
      x: x * overlayScale + insetCorrection.x,
      y: y * overlayScale + insetCorrection.y
    )
  }

  /// Label origin in buffer pixels, vertically centered within the visible header.
  /// The visible header spans y=0 to y=headerHeight in buffer coordinates,
  /// so no `insetCorrection.y` is applied (unlike shapes positioned via `bufferRect`).
  public func labelOrigin(padding: CGFloat, ascent: CGFloat, descent: CGFloat) -> CGPoint {
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
  public func labelFontSize(_ baseFontSize: CGFloat) -> CGFloat {
    baseFontSize * overlayScale
  }

  // MARK: - Bars

  /// Default bar height in logical pixels. Matches the runner's `BORDER_TOP` constant.
  public static let defaultBarHeight: Int = 24

  /// Bar font size in buffer pixels, derived from the bar's logical height.
  public func barFontSize() -> CGFloat {
    let logicalHeight = CGFloat(Self.defaultBarHeight)
    let padding: CGFloat = 4
    return (logicalHeight - padding * 2) * overlayScale
  }

  /// Bar height in buffer pixels.
  public func barHeight() -> CGFloat {
    CGFloat(Self.defaultBarHeight) * overlayScale
  }

  /// Bar height in logical pixels, rounded to even for H.264/NV12 compatibility.
  public static func barHeightEven(logicalHeight: Int = defaultBarHeight) -> Int {
    logicalHeight % 2 == 0 ? logicalHeight : logicalHeight + 1
  }

  /// Bar Y position in buffer pixels for a given position.
  public func barY(position: String) -> CGFloat {
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
