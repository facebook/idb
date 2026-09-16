/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The output dimensions shared by the encoder pipeline and the composited-frame pool: the source
/// scaled by the optional factor (only factors strictly between 0 and 1 apply), expanded by the edge
/// insets, then rounded up to even — H.264 and NV12 require even dimensions. The VideoToolbox
/// session and the composited pool must agree on these exactly (a mismatch feeds the encoder frames
/// of a different size than it was created for, distorting the output), so both sites derive them
/// from this single computation.
struct VideoOutputDimensions: Equatable {
  let width: Int
  let height: Int

  static func calculate(sourceWidth: Int, sourceHeight: Int, scaleFactor: Double?, edgeInsets: VideoStreamEdgeInsets) -> VideoOutputDimensions {
    var width = sourceWidth
    var height = sourceHeight
    if let scaleFactor, scaleFactor > 0, scaleFactor < 1 {
      width = Int(floor(scaleFactor * Double(sourceWidth)))
      height = Int(floor(scaleFactor * Double(sourceHeight)))
    }
    width += Int(edgeInsets.left + edgeInsets.right)
    height += Int(edgeInsets.top + edgeInsets.bottom)
    width += width % 2
    height += height % 2
    return VideoOutputDimensions(width: width, height: height)
  }
}
