/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreVideo
import FBControlCore
import FBSimulatorControl
import Foundation

/// Frame pusher abstraction. Concrete pushers convert + write frames to the consumer.
protocol FramePusher: AnyObject {
  func setup(source: VideoFrameSource, edgeInsets: VideoStreamEdgeInsets) throws
  func tearDown() throws
  func writeEncodedFrame(
    _ pixelBuffer: CVPixelBuffer,
    frameNumber: UInt,
    timeAtFirstFrame: TimeInterval,
    frameDuration: TimeInterval,
    forceKeyFrame: Bool
  ) throws
  /// Starts the encoder on a throwaway frame whose output is discarded, so the first frame written does not wait
  /// for it. Called once, after `setup`.
  func warm(with pixelBuffer: CVPixelBuffer) throws
  /// Hands on every frame the encoder still holds, without ending it, so a pusher set aside and taken up again
  /// cannot emit frames older than those written since.
  func completeFrames()
  /// The source surface changed while the frame was being read; counted in the pusher's stats.
  func recordTornFrame()
  func currentStats() -> VideoEncoderStats?
}

extension FramePusher {
  func warm(with pixelBuffer: CVPixelBuffer) throws {}
  func completeFrames() {}
  func recordTornFrame() {}
  func currentStats() -> VideoEncoderStats? { nil }
}

/// Set-up frame pushers keyed by the source each was set up for, so a stream that switches between displays
/// takes one rather than starting an encoder on the switch.
struct FramePusherPool {
  private var pushers: [VideoFrameSource: any FramePusher] = [:]

  func contains(_ source: VideoFrameSource) -> Bool {
    pushers[source] != nil
  }

  mutating func take(_ source: VideoFrameSource) -> (any FramePusher)? {
    pushers.removeValue(forKey: source)
  }

  /// Returns the pusher already kept for `source`, which the caller tears down.
  mutating func keep(_ pusher: any FramePusher, for source: VideoFrameSource) -> (any FramePusher)? {
    pushers.updateValue(pusher, forKey: source)
  }

  mutating func removeAll() -> [any FramePusher] {
    defer { pushers = [:] }
    return Array(pushers.values)
  }
}
