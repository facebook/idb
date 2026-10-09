/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import CoreVideo
import FBControlCore

/// Set-up frame pushers keyed by the source each was set up for, so a stream that switches between displays
/// takes one rather than starting an encoder on the switch.
struct FramePusherPool {

  /// What a pusher's setup reads from its source pixel buffer.
  struct Source: Hashable, CustomStringConvertible {
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

    var description: String { "\(width)x\(height) \(pixelFormat.fourCharCodeString)" }
  }

  private var pushers: [Source: any FramePusher] = [:]

  func contains(_ source: Source) -> Bool {
    pushers[source] != nil
  }

  mutating func take(_ source: Source) -> (any FramePusher)? {
    pushers.removeValue(forKey: source)
  }

  /// Returns the pusher already kept for `source`, which the caller tears down.
  mutating func keep(_ pusher: any FramePusher, for source: Source) -> (any FramePusher)? {
    pushers.updateValue(pusher, forKey: source)
  }

  mutating func removeAll() -> [any FramePusher] {
    defer { pushers = [:] }
    return Array(pushers.values)
  }
}
