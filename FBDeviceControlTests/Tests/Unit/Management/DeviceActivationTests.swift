/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBDeviceControl
import Testing

@Suite
struct DeviceActivationTests {

  @Test
  func activationRequestsIdentifyIdbInTheirUserAgent() {
    #expect(deviceActivationUserAgent == "idb (FBDeviceControl.Device)")
  }
}
