/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBDeviceControl
import Foundation
import Testing

private let MobileActivationService = "com.apple.mobileactivationd"
private let ECID: UInt = 12345

/// Erasing an activated device: it is detected, accepts the erase, then drops off and comes back
/// as it reboots.
@MainActor
// Serialized: the restorable fake is held statically, and its notifications arrive on the main queue.
@Suite(.serialized)
struct DeviceEraseStrategyTests {

  private let amDevice = FakeAMDevice()
  private let restorable = FakeRestorableDevice(ecid: ECID)

  private func makeDevice() -> Device {
    amDevice.values["UniqueChipID"] = NSNumber(value: ECID)
    amDevice.restorable = restorable
    let device = amDevice.makeDevice()
    amDevice.service(MobileActivationService).repeatingReply = ["Value": "Activated"]
    return device
  }

  @Test
  func erasingWaitsForTheDeviceToRebootAfterAcceptingTheErase() async throws {
    let device = makeDevice()

    try await device.erase()

    #expect(
      restorable.events == [
        "register",
        "connected",
        "erase:fake-udid",
        "erase_callback:-10",
        "disconnected",
        "connected",
      ])
  }

  @Test
  func erasingFailsWhenTheDeviceRefusesTheErase() async throws {
    let device = makeDevice()
    restorable.eraseProgress = 0

    do {
      try await device.erase()
      Issue.record("An erase the device refused should fail")
    } catch let DeviceEraseError.badEraseCallback(value, expected) {
      #expect(value == 0)
      #expect(expected == -10)
    }
  }
}
