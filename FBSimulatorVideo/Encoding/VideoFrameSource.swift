/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import CoreVideo
import FBControlCore
import FBSimulatorControl

/// What a frame pusher is set up for: the size and pixel format of the frames it is given.
struct VideoFrameSource: Hashable, CustomStringConvertible {
  let width: Int
  let height: Int
  let pixelFormat: OSType

  init(width: Int, height: Int, pixelFormat: OSType) {
    self.width = width
    self.height = height
    self.pixelFormat = pixelFormat
  }

  init(_ pixelBuffer: CVPixelBuffer) {
    self.init(
      width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer), pixelFormat: CVPixelBufferGetPixelFormatType(pixelBuffer))
  }

  /// Nil for a size that is not a positive whole number of pixels.
  init?(_ size: CGSize, pixelFormat: OSType) {
    guard let width = Int(exactly: size.width), let height = Int(exactly: size.height), width > 0, height > 0 else {
      return nil
    }
    self.init(width: width, height: height, pixelFormat: pixelFormat)
  }

  /// The source as the interface shows it: a quarter turn swaps its width and height.
  func rotated(_ rotation: SimulatorDisplayRotation) -> VideoFrameSource {
    rotation.isQuarterTurn ? VideoFrameSource(width: height, height: width, pixelFormat: pixelFormat) : self
  }

  var description: String { "\(width)x\(height) \(pixelFormat.fourCharCodeString)" }
}
