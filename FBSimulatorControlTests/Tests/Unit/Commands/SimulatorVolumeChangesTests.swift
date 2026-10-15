/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import Testing

@Suite
struct SimulatorVolumeChangesTests {
  @Test(arguments: [UInt64(0), 60, 100])
  func currentValueNativeChangeAndCancellation(initial: UInt64) async throws {
    let fixture = try SimulatorNotificationFixture()
    fixture.device.change(state: initial)
    let values = try await fixture.simulator.audio.volumeChanges()
    #expect(fixture.device.observedName == "com.apple.springboard.volumestate")
    let (received, receive) = AsyncStream.makeStream(of: Double.self)
    let consumer = Task {
      for try await value in values { receive.yield(value) }
    }
    var iterator = received.makeAsyncIterator()
    #expect(await iterator.next() == Double(initial) / 100)
    fixture.device.change(state: 30)
    #expect(await iterator.next() == 0.3)
    consumer.cancel()
    _ = await consumer.result
    receive.finish()
    #expect(fixture.device.cancelled)
  }
}
