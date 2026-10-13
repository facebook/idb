/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBDeviceControl
import Testing

@MainActor
@Suite(.serialized)
struct DeviceSocketForwardingCommandsTests {
  @Test
  func zeroPortFailsBeforeConnectingOrRunningTheOperation() async {
    let amDevice = FakeAMDevice()
    let device = amDevice.makeDevice()
    amDevice.clearEvents()

    await #expect {
      try await device.socketForwarding.withPortConnection(port: 0) { _ in
        Issue.record("Unexpected socket operation")
      }
    } throws: {
      guard case .invalidPort(0) = $0 as? DeviceSocketForwardingError else { return false }
      return true
    }
    #expect(amDevice.events.isEmpty)
  }

  @Test(arguments: [Int32.min, -1, 0, 65536, Int32.max])
  func invalidFileForwardingPortFailsBeforeConnecting(remotePort: Int32) async {
    let amDevice = FakeAMDevice()
    let device = amDevice.makeDevice()
    amDevice.clearEvents()

    await #expect {
      try await device.socketForwarding.drainLocalFileInput(-1, localFileOutput: -1, remotePort: remotePort)
    } throws: {
      guard case let .invalidPort(port) = $0 as? DeviceSocketForwardingError else { return false }
      return port == Int(remotePort)
    }
    #expect(amDevice.events.isEmpty)
  }
}
