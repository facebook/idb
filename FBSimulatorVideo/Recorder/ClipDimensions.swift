/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import Foundation

/// What a clip of a recording is re-encoded at: the recording's own frame size and data rate,
/// adjusted to values an H.264 encoder accepts.
public struct ClipDimensions: Equatable, Sendable {
  public let width: Int
  public let height: Int
  public let bitRate: Int

  /// H.264 rejects odd dimensions, so each is rounded down to an even number of pixels. A recording
  /// that reports no usable data rate — zero, infinite or NaN — falls back to four bits per pixel,
  /// which will not starve a simulator capture of flat UI.
  public init(size: CGSize, dataRate: Float) {
    let width = Self.even(size.width)
    let height = Self.even(size.height)
    self.width = width
    self.height = height
    self.bitRate = dataRate.isFinite && dataRate > 0 ? Int(dataRate) : width * height * 4
  }

  private static func even(_ pixels: CGFloat) -> Int {
    guard pixels.isFinite, pixels >= 2 else {
      return 2
    }
    let whole = Int(pixels)
    return whole - whole % 2
  }
}
