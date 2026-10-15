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
struct SimulatorRingerChangesTests {
  @Test(arguments: [false, true])
  func currentValueNativeChangeAndCancellation(initial: Bool) async throws {
    let fixture = try SimulatorNotificationFixture()
    fixture.device.change(state: initial ? 1 : 0)
    let values = try await fixture.simulator.audio.ringerChanges()
    #expect(fixture.device.observedName == "com.apple.springboard.ringerstate")
    let (received, receive) = AsyncStream.makeStream(of: Bool.self)
    let consumer = Task {
      for try await value in values { receive.yield(value) }
    }
    var iterator = received.makeAsyncIterator()
    #expect(await iterator.next() == initial)
    fixture.device.change(state: initial ? 0 : 1)
    #expect(await iterator.next() == !initial)
    consumer.cancel()
    _ = await consumer.result
    receive.finish()
    #expect(fixture.device.cancelled)
  }
}
