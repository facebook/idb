/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

/// Carries a device double into a detached task.
///
/// `@unchecked Sendable`: the double behind the reinterpretation is only reached from the
/// CoreSimulator notification handler, on the queue that handler registered with.
private struct DeviceBox: @unchecked Sendable {
  let device: SimDevice
}

final class CoreSimulatorNotifierTests: XCTestCase {

  private var notifier: SimDeviceNotifierDouble!
  private var device: SimDeviceDouble!

  override func setUp() {
    super.setUp()
    notifier = SimDeviceNotifierDouble()
    device = SimDeviceDouble()
    device.state = UInt64(TargetState.booted.rawValue)
    device.notificationManager = notifier
  }

  private func resolveLeavesBooted() -> Task<Void, Error> {
    let box = DeviceBox(device: SimulatorTestSupport.asDevice(self.device))
    return Task.detached {
      try await CoreSimulatorNotifier.resolveLeavesState(.booted, for: box.device)
    }
  }

  /// The wait registers its handler on the detached task, so the test cannot post until it has.
  private func waitForRegistration(timeout: TimeInterval = 5) {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while notifier.registeredHandleCount == 0 && Date() < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    }
  }

  /// Unregistration lands on the notifier's own queue after the waiter has been woken.
  private func waitForUnregistration(timeout: TimeInterval = 5) {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while notifier.registeredHandleCount > 0 && Date() < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    }
  }

  func testResolvesWhenTheDeviceReportsADifferentState() async throws {
    let task = resolveLeavesBooted()
    waitForRegistration()
    XCTAssertEqual(notifier.registeredHandleCount, 1)

    notifier.post(["notification": "device_state", "new_state": NSNumber(value: TargetState.shutdown.rawValue)])

    try await task.value
  }

  func testUnregistersTheHandlerOnceResolved() async throws {
    let task = resolveLeavesBooted()
    waitForRegistration()

    notifier.post(["notification": "device_state", "new_state": NSNumber(value: TargetState.shutdown.rawValue)])
    try await task.value

    XCTAssertEqual(notifier.unregisteredHandles.count, 1)
    XCTAssertEqual(notifier.registeredHandleCount, 0)
  }

  func testDoesNotResolveWhenTheDeviceReportsTheSameState() {
    let task = resolveLeavesBooted()
    waitForRegistration()

    notifier.post(["notification": "device_state", "new_state": NSNumber(value: TargetState.booted.rawValue)])

    // The handler outliving the notification is the wait still being live: it is unregistered as
    // part of finishing, whether that is by resolution or by cancellation. Unregistration lands
    // asynchronously, so the pin is that it has not happened within a bounded wait.
    waitForUnregistration(timeout: 0.5)
    XCTAssertEqual(notifier.registeredHandleCount, 1)
    task.cancel()
  }

  func testIgnoresNotificationsThatAreNotStateChanges() {
    let task = resolveLeavesBooted()
    waitForRegistration()

    notifier.post(["notification": "device_name", "new_state": NSNumber(value: TargetState.shutdown.rawValue)])

    waitForUnregistration(timeout: 0.5)
    XCTAssertEqual(notifier.registeredHandleCount, 1)
    task.cancel()
  }

  func testIgnoresStateChangesThatCarryNoNewState() {
    let task = resolveLeavesBooted()
    waitForRegistration()

    notifier.post(["notification": "device_state"])

    waitForUnregistration(timeout: 0.5)
    XCTAssertEqual(notifier.registeredHandleCount, 1)
    task.cancel()
  }

  func testUnregistersTheHandlerWhenCancelled() async throws {
    let task = resolveLeavesBooted()
    waitForRegistration()
    XCTAssertEqual(notifier.registeredHandleCount, 1)

    task.cancel()
    do {
      try await task.value
      XCTFail("Expected the cancelled wait to throw")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }

    XCTAssertEqual(notifier.unregisteredHandles.count, 1)
    XCTAssertEqual(notifier.registeredHandleCount, 0)
  }
}
