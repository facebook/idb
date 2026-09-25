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
}
