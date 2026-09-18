/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Where a recording's media time zero falls on the wall clock.
///
/// The encoder stamps every presentation timestamp as an offset from `systemUptime` at the frame
/// it was first pushed, and the file's timeline is anchored at the first sample actually muxed, so
/// media zero is `uptimeAtFirstFrame + anchor` on the uptime clock. Saying where that falls on the
/// wall clock takes a reading of both clocks, because only one of them is monotonic.
public struct MediaOrigin: Equatable, Sendable {
  /// `systemUptime` when the first frame was pushed into the encoder.
  public let uptimeAtFirstFrame: TimeInterval

  public init(uptimeAtFirstFrame: TimeInterval) {
    self.uptimeAtFirstFrame = uptimeAtFirstFrame
  }

  /// The Unix timestamp of media time zero, for a recording anchored `anchor` seconds after the
  /// first pushed frame, from one adjacent pair of clock readings.
  public func startedAt(
    anchor: TimeInterval,
    uptimeNow: TimeInterval,
    wallClockNow: TimeInterval
  ) -> TimeInterval {
    wallClockNow - (uptimeNow - (uptimeAtFirstFrame + anchor))
  }
}
