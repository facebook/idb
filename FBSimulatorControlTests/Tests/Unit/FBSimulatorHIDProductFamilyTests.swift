/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Testing

/// Coverage of the product-family facts the HID transports consult.
@Suite("HID product family")
struct FBSimulatorHIDProductFamilyTests {

  @Test(
    "Every family but Apple TV has a touchscreen",
    arguments: [
      (FBControlCoreProductFamily.familyiPhone, true),
      (.familyiPad, true),
      (.familyAppleWatch, true),
      (.familyAppleTV, false),
    ])
  func hasTouchscreen(family: FBControlCoreProductFamily, expected: Bool) {
    #expect(family.hasTouchscreen == expected)
  }
}
