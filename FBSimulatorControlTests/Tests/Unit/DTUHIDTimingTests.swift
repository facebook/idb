/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Testing

/// Coverage of the timing the DTUHID transport applies around its sends.
@Suite("DTUHID timing")
struct DTUHIDTimingTests {

  @Test("A connection is treated as ready to carry an event as soon as it is opened")
  func preparation() {
    // BUG: dtuhidd activates the services that carry events only once the connection has a peer, and
    // an XPC connection gains one on its first message — so the first event is sent into a connection
    // with no service to receive it, and dropped. Flipped in the following commit.
    #expect(DTUHIDTiming.preparation == .none)
  }
}
