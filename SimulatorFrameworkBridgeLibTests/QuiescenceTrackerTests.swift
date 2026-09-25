/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeRuntime
@_implementationOnly import SimulatorFrameworkBridgeSupport
import XCTest

final class QuiescenceTrackerTests: XCTestCase {
  private var tracker = QuiescenceTracker(busyThreshold: 0.02, quietWindow: 0.25)

  private func requestBoth(at time: TimeInterval) {
    tracker.requested(.runLoopIdle, at: time)
    tracker.requested(.animationsInactive, at: time)
  }

  func testTheStateIsUnknownUntilEverySignalIsAnsweredOrBusy() {
    requestBoth(at: 0)
    XCTAssertNil(tracker.state(at: 0.01))
    tracker.answered(.runLoopIdle, at: 0.001)
    XCTAssertNil(tracker.state(at: 0.01))
    XCTAssertEqual(tracker.state(at: 0.02), .busy([.animationsInactive]))
  }

  func testPromptAnswersSettleThenGoQuietOnceTheWindowPasses() {
    requestBoth(at: 0)
    tracker.answered(.runLoopIdle, at: 0.001)
    tracker.answered(.animationsInactive, at: 0.002)
    XCTAssertEqual(tracker.state(at: 0.1), .settling)
    XCTAssertEqual(tracker.state(at: 0.252), .quiet)
  }

  func testAPromptReArmDoesNotRestartTheWindow() {
    requestBoth(at: 0)
    tracker.answered(.runLoopIdle, at: 0.001)
    tracker.answered(.animationsInactive, at: 0.001)
    tracker.requested(.runLoopIdle, at: 0.05)
    tracker.answered(.runLoopIdle, at: 0.051)
    XCTAssertEqual(tracker.state(at: 0.251), .quiet)
  }

  func testABusyAnswerRestartsTheWindowFromTheAnswer() {
    requestBoth(at: 0)
    tracker.answered(.runLoopIdle, at: 0.001)
    tracker.answered(.animationsInactive, at: 0.001)
    tracker.requested(.animationsInactive, at: 1)
    XCTAssertEqual(tracker.state(at: 1.5), .busy([.animationsInactive]))
    tracker.answered(.animationsInactive, at: 2)
    XCTAssertEqual(tracker.state(at: 2.1), .settling)
    XCTAssertEqual(tracker.state(at: 2.25), .quiet)
  }

  func testAnAnswerThatWasNotRequestedIsIgnored() {
    tracker.answered(.runLoopIdle, at: 0)
    tracker.answered(.animationsInactive, at: 0)
    XCTAssertNil(tracker.state(at: 1))
  }

  func testTheNextDeadlineIsTheEarliestThresholdOrWindowEnd() throws {
    requestBoth(at: 0)
    XCTAssertEqual(try XCTUnwrap(tracker.nextDeadline(after: 0)), 0.02, accuracy: 1e-9)
    tracker.answered(.runLoopIdle, at: 0.001)
    tracker.answered(.animationsInactive, at: 0.004)
    XCTAssertEqual(try XCTUnwrap(tracker.nextDeadline(after: 0.01)), 0.254, accuracy: 1e-9)
    tracker.requested(.runLoopIdle, at: 0.1)
    XCTAssertEqual(try XCTUnwrap(tracker.nextDeadline(after: 0.1)), 0.12, accuracy: 1e-9)
    XCTAssertNil(tracker.nextDeadline(after: 0.3), "a busy signal changes only when it is answered")
  }

  func testResetForgetsEverything() {
    requestBoth(at: 0)
    tracker.answered(.runLoopIdle, at: 0.001)
    tracker.answered(.animationsInactive, at: 0.001)
    tracker.reset()
    XCTAssertNil(tracker.state(at: 1))
    XCTAssertNil(tracker.nextDeadline(after: 1))
  }
}
