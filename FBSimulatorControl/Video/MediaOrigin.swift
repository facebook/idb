/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Where a recording's media time zero falls on the wall clock.
///
/// The file's timeline is anchored at the first sample actually muxed, which the encoder stamps
/// relative to the frame it was first pushed, so media zero is `anchor` seconds after that frame.
/// When that frame was captured is read from the wall clock as it was captured: a clock read any
/// later has had time to be set, and would move a moment that has already happened.
public struct MediaOrigin: Equatable, Sendable {
  /// The Unix timestamp when the first frame was pushed into the encoder, read then.
  public let wallClockAtFirstFrame: TimeInterval

  public init(wallClockAtFirstFrame: TimeInterval) {
    self.wallClockAtFirstFrame = wallClockAtFirstFrame
  }

  /// The Unix timestamp of media time zero, for a recording whose file is anchored `anchor`
  /// seconds after the first pushed frame.
  public func startedAt(anchor: TimeInterval) -> TimeInterval {
    wallClockAtFirstFrame + anchor
  }
}
