/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
@testable import FBSimulatorServices
import Foundation
import Testing

@Suite
struct SimulatorContentSizeChangesTests {
  @Test func currentValueNativeChangeAndCancellation() async throws {
    let fixture = try SimulatorNotificationFixture()
    let values = try await fixture.simulator.preferences.contentSizeChanges()
    #expect(fixture.device.observedName == "ApplePreferredContentSizeCategoryChangedNotification")
    let (received, receive) = AsyncStream.makeStream(of: SimulatorContentSizeCategory.self)
    let consumer = Task {
      for try await value in values { receive.yield(value) }
    }
    var iterator = received.makeAsyncIterator()
    #expect(await iterator.next() == .large)
    fixture.device.change(size: 5)
    #expect(await iterator.next() == .extraLarge)
    consumer.cancel()
    _ = await consumer.result
    receive.finish()
    #expect(fixture.device.cancelled)
  }
}
