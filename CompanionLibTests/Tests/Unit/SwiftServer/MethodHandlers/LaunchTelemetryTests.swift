/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import Foundation
import Testing

/// A clock that reads `start`, then `start` plus each elapsed value in turn.
private func readings(_ elapsed: Duration...) -> () -> ContinuousClock.Instant {
  let start = ContinuousClock.now
  var remaining = [start] + elapsed.map { start + $0 }
  return { remaining.removeFirst() }
}

private struct Refused: Error {}

@Suite struct LaunchTelemetryTests {

  @Test func eachStageReportsItsOwnColumnInWholeMilliseconds() async {
    let call = CallTelemetry()

    let prepared = await LaunchStage.audioInjection.measure(into: call, now: readings(.microseconds(161_900))) { "prepared" }
    await LaunchStage.environmentReplacement.measure(into: call, now: readings(.microseconds(400))) {}
    await LaunchStage.launch.measure(into: call, now: readings(.seconds(2))) {}

    #expect(prepared == "prepared")
    #expect(call.columnDescriptions == ["audio_injection_ms=161", "env_replace_ms=0", "launch_ms=2000"])
  }

  @Test func aLaunchThatFailsStillReportsHowLongItTook() async {
    let call = CallTelemetry()

    await #expect(throws: Refused.self) {
      try await LaunchStage.launch.measure(into: call, now: readings(.milliseconds(7))) { throw Refused() }
    }

    #expect(call.ints == ["launch_ms": 7])
  }

  @Test func outsideACallTheStageStillRuns() async {
    let value = await LaunchStage.launch.measure(into: nil, now: readings(.milliseconds(1))) { 42 }

    #expect(value == 42)
  }
}
