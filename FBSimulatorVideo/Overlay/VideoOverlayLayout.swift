/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreVideo

/// Lays a stream's overlay out for its canvas. The stream asks again whenever its canvas changes, as on a rotation
/// or a switch to a display of another size, and composites the buffer it is given.
public protocol VideoOverlayLayout: AnyObject, Sendable {
  /// The overlay buffer for a canvas whose screen area is `canvasPixelWidth` by `canvasPixelHeight`, showing a screen
  /// of `screenPixelWidth` by `screenPixelHeight`, both in pixels as the interface shows them. A screen of another
  /// shape than the canvas is letterboxed into it.
  func layOut(screenPixelWidth: Int, screenPixelHeight: Int, canvasPixelWidth: Int, canvasPixelHeight: Int) -> CVPixelBuffer

  /// A one-off buffer with the overlay drawn as it is now, laid out for a canvas that is exactly a screen of this many
  /// pixels. The buffer `layOut` returned is left as it is.
  func snapshot(screenPixelWidth: Int, screenPixelHeight: Int) -> CVPixelBuffer
}
