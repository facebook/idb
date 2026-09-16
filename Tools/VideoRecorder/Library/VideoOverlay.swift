/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import FBSimulatorControl
import Foundation

public extension Simulator {
  /// Compute the buffer-pixel edge insets and the overlay renderer for a video session. Shared by
  /// `videoStream` and `videoRecord` so the stream and record paths reserve bar regions and map
  /// overlay coordinates identically.
  @MainActor
  func prepareVideoOverlay(edgeInsets: VideoStreamEdgeInsets, scaleFactor: Double?, overlayCoordSpace: OverlayCoordSpace) -> (scaledInsets: VideoStreamEdgeInsets, renderer: OverlayRenderer) {
    let screenInfo = self.screenInfo
    let pixelWidth = Int(screenInfo?.widthPixels ?? 640)
    let pixelHeight = Int(screenInfo?.heightPixels ?? 480)
    let retinaScale = CGFloat(screenInfo?.scale ?? 2.0)
    let scale = scaleFactor ?? 1.0
    // edgeInsets are in logical points (the same unit jeste2e uses for overlay shape
    // coordinates and the runner's BORDER_TOP constant). SimulatorVideoStream expects
    // its edge insets in buffer pixels, so we multiply by videoScale AND retinaScale.
    // Missing the retinaScale factor causes the reserved bar region to be too small
    // by a factor of retinaScale (e.g. 1/3 the intended size on a 3x retina device),
    // which makes runner-driven overlay shapes drawn at logical y=0..BORDER_TOP visually
    // overlap the simulator's iOS status bar instead of sitting cleanly above it.
    let insetScale = scale * Double(retinaScale)
    let scaledInsets = VideoStreamEdgeInsets(
      top: UInt(Double(edgeInsets.top) * insetScale),
      bottom: UInt(Double(edgeInsets.bottom) * insetScale),
      left: UInt(Double(edgeInsets.left) * insetScale),
      right: UInt(Double(edgeInsets.right) * insetScale)
    )

    // All overlay coordinate math is encapsulated in the transform.
    let transform = OverlayCoordinateTransform(
      screenPixelWidth: pixelWidth,
      screenPixelHeight: pixelHeight,
      retinaScale: retinaScale,
      videoScale: CGFloat(scale),
      borderTop: Int(edgeInsets.top),
      scaledBorderTop: Int(scaledInsets.top),
      borderBottom: Int(edgeInsets.bottom),
      scaledBorderBottom: Int(scaledInsets.bottom),
      coordSpace: overlayCoordSpace
    )
    let simLogger = self.logger
    simLogger.info().log("Overlay setup: screenInfo=\(pixelWidth)x\(pixelHeight)@\(retinaScale)x, videoScale=\(scale), buffer=\(transform.bufferWidth)x\(transform.bufferHeight), overlayScale=\(transform.overlayScale), insetCorrection=\(transform.insetCorrection), coordSpace=\(overlayCoordSpace.rawValue), scaledInsets=t\(scaledInsets.top)/b\(scaledInsets.bottom)/l\(scaledInsets.left)/r\(scaledInsets.right)")
    let renderer = OverlayRenderer(transform: transform)
    renderer.logger = simLogger
    return (scaledInsets, renderer)
  }

}
