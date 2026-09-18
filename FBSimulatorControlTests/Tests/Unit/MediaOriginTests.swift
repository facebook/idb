/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import Testing

@Suite("Media origin")
struct MediaOriginTests {
  /// A recording whose first frame was pushed 100 seconds after boot, with the file anchored on
  /// that same frame, read 60 seconds later on a wall clock that has not moved.
  private let origin = MediaOrigin(uptimeAtFirstFrame: 100)

  @Test func reportsWhenTheFirstFrameWasCaptured() {
    let startedAt = origin.startedAt(anchor: 0, uptimeNow: 160, wallClockNow: 1_000_060)

    #expect(startedAt == 1_000_000)
  }

  @Test func countsTheFileSAnchorAsPartOfTheRecording() {
    // The file is anchored on the first sample muxed, which is 2 seconds of encoder latency after
    // the first frame was pushed, so media zero is 2 seconds later than that frame.
    let startedAt = origin.startedAt(anchor: 2, uptimeNow: 160, wallClockNow: 1_000_060)

    #expect(startedAt == 1_000_002)
  }

  @Test func doesNotDriftWithHowLongTheRecordingRan() {
    let shortly = origin.startedAt(anchor: 0, uptimeNow: 101, wallClockNow: 1_000_001)
    let muchLater = origin.startedAt(anchor: 0, uptimeNow: 700, wallClockNow: 1_000_600)

    #expect(shortly == muchLater)
  }

  @Test func movesWhenTheWallClockIsSetDuringTheRecording() {
    // The wall clock jumped forward a minute after the first frame was captured: the same
    // recording, read through a clock that has been set since.
    let startedAt = origin.startedAt(anchor: 0, uptimeNow: 160, wallClockNow: 1_000_120)

    // BUG: the first frame was captured at 1_000_000, and moving the wall clock afterwards cannot
    // change when that happened. The origin is worked out from a reading taken when the recording
    // stopped, so a clock that was set in between carries the answer with it — flipped in the
    // following commit.
    #expect(startedAt == 1_000_060)
  }
}
