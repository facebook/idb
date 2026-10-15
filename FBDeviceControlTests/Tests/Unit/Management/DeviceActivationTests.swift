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
    // BUG: names a source file that no longer exists rather than the activating type — flipped in the following commit.
    #expect(deviceActivationUserAgent == "idb (https://github.com/facebook/idb/blob/main/FBDeviceControl/Strategies/DeviceActivationStrategy.swift)")
  }
}
