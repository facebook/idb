/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBDeviceControl
import Testing
import XCTestBootstrap

@Suite
struct DeviceXCTestCommandsTests {

  @Test
  func overwriteXCTestRunPropertiesWithBaseProperties() {
    let baseProperties: [String: Any] = [
      "BundleIDBase": [
        "NoOverwrite": "Hello",
        "OverwriteMe": "Hi",
      ]
    ]

    let newProperties: [String: Any] = [
      "StubBundleId": [
        "OverwriteMe": "Hi overwrite!",
        "NoExist": "It's not defined in base so it won't be used.",
      ]
    ]

    let expectedProperties: [String: Any] = [
      "BundleIDBase": [
        "NoOverwrite": "Hello",
        "OverwriteMe": "Hi overwrite!",
      ]
    ]

    let realProperties = XcodeBuildOperation.overwriteXCTestRunProperties(withBaseProperties: baseProperties, newProperties: newProperties)

    #expect((realProperties as NSDictionary) == (expectedProperties as NSDictionary))
  }
}
