/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
@testable import FBSimulatorVideo
import FBVideoCore
import Foundation
import Testing

@Suite("Media origin")
struct MediaOriginTests {
  /// A recording whose first frame was captured at 1_000_000, read from the wall clock then.
  private let origin = MediaOrigin(wallClockAtFirstFrame: 1_000_000)

  @Test func reportsWhenTheFirstFrameWasCaptured() {
    #expect(origin.startedAt(anchor: 0) == 1_000_000)
  }

  @Test func countsTheFileSAnchorAsPartOfTheRecording() {
    // The file is anchored on the first sample muxed, which is 2 seconds of encoder latency after
    // the first frame was pushed, so media zero is 2 seconds later than that frame.
    #expect(origin.startedAt(anchor: 2) == 1_000_002)
  }

  @Test func placesMediaZeroOnTheHostClockTheSameWay() {
    let hostTime: UInt64 = 1 << 40
    let origin = MediaOrigin(wallClockAtFirstFrame: 1_000_000, hostTimeAtFirstFrame: hostTime)
    let later = origin.startHostTime(anchor: 2)
    let earlier = origin.startHostTime(anchor: -2)

    #expect(later > hostTime)
    #expect(abs(MediaOrigin.seconds(fromHostTime: hostTime, to: later) - 2) < 1e-6)
    #expect(abs(MediaOrigin.seconds(fromHostTime: hostTime, to: earlier) + 2) < 1e-6)
    #expect(abs(MediaOrigin.seconds(fromHostTime: later, to: earlier) + 4) < 1e-6)
  }
}
