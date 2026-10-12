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
  /// The overlay buffer for a canvas showing a screen of this many pixels, as the interface shows it.
  func layOut(screenPixelWidth: Int, screenPixelHeight: Int) -> CVPixelBuffer
}
