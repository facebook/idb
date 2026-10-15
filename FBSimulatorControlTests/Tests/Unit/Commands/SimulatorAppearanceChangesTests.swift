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
struct SimulatorAppearanceChangesTests {
  @Test func currentValueNativeChangeAndCancellation() async throws {
    let fixture = try SimulatorNotificationFixture()
    let values = try await fixture.simulator.preferences.appearanceChanges()
    #expect(fixture.device.observedName == "com.apple.UIKit.SystemUIServiceUserInterfaceStyleNotification")
    let (received, receive) = AsyncStream.makeStream(of: SimulatorAppearance.self)
    let consumer = Task {
      for try await value in values { receive.yield(value) }
    }
    var iterator = received.makeAsyncIterator()
    #expect(await iterator.next() == .light)
    fixture.device.change(style: 2)
    #expect(await iterator.next() == .dark)
    consumer.cancel()
    _ = await consumer.result
    receive.finish()
    #expect(fixture.device.cancelled)
  }
}
