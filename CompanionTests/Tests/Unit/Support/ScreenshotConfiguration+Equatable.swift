/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore

// FBControlCore does not compare screenshot configurations, so it does not carry the conformance;
// the translation tests compare whole values, so they declare it here.

extension ScreenshotConfiguration: @retroactive Equatable {
  public static func == (lhs: ScreenshotConfiguration, rhs: ScreenshotConfiguration) -> Bool {
    lhs.encoding == rhs.encoding
      && lhs.cropRect == rhs.cropRect
      && lhs.scale == rhs.scale
      && lhs.unit == rhs.unit
      && lhs.display == rhs.display
  }
}
