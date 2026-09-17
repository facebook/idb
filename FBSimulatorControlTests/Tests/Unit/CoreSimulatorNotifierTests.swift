/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

final class CoreSimulatorNotifierTests: XCTestCase {

  private var notifier: SimDeviceNotifierDouble!
  private var device: SimDeviceDouble!

  override func setUp() {
    super.setUp()
    notifier = SimDeviceNotifierDouble()
    device = SimDeviceDouble()
    device.state = UInt64(FBTargetState.booted.rawValue)
    device.notificationManager = notifier
  }

  private func resolveLeavesBooted() -> FBFuture<NSNull> {
    CoreSimulatorNotifier.resolveLeavesState(.booted, for: SimulatorTestSupport.asDevice(device))
  }

  /// Teardown is hung off the future's completion and so lands on the notifier's own queue,
  /// after the waiter has been woken.
  private func waitForUnregistration(timeout: TimeInterval = 5) {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while notifier.registeredHandleCount > 0 && Date() < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    }
  }

  func testResolvesWhenTheDeviceReportsADifferentState() throws {
    let future = resolveLeavesBooted()
    XCTAssertEqual(notifier.registeredHandleCount, 1)

    notifier.post(["notification": "device_state", "new_state": NSNumber(value: FBTargetState.shutdown.rawValue)])

    XCTAssertNotNil(try future.await(withTimeout: 1))
  }

  func testUnregistersTheHandlerOnceResolved() throws {
    let future = resolveLeavesBooted()

    notifier.post(["notification": "device_state", "new_state": NSNumber(value: FBTargetState.shutdown.rawValue)])
    _ = try future.await(withTimeout: 1)
    waitForUnregistration()

    XCTAssertEqual(notifier.unregisteredHandles.count, 1)
    XCTAssertEqual(notifier.registeredHandleCount, 0)
  }

  func testDoesNotResolveWhenTheDeviceReportsTheSameState() {
    let future = resolveLeavesBooted()

    notifier.post(["notification": "device_state", "new_state": NSNumber(value: FBTargetState.booted.rawValue)])

    XCTAssertEqual(future.state, .running)
  }

  func testIgnoresNotificationsThatAreNotStateChanges() {
    let future = resolveLeavesBooted()

    notifier.post(["notification": "device_name", "new_state": NSNumber(value: FBTargetState.shutdown.rawValue)])

    XCTAssertEqual(future.state, .running)
  }

  func testIgnoresStateChangesThatCarryNoNewState() {
    let future = resolveLeavesBooted()

    notifier.post(["notification": "device_state"])

    XCTAssertEqual(future.state, .running)
  }

  func testUnregistersTheHandlerWhenCancelled() throws {
    let future = resolveLeavesBooted()
    XCTAssertEqual(notifier.registeredHandleCount, 1)

    _ = try? future.cancel().await(withTimeout: 1)
    waitForUnregistration()

    XCTAssertEqual(notifier.unregisteredHandles.count, 1)
    XCTAssertEqual(notifier.registeredHandleCount, 0)
  }
}
