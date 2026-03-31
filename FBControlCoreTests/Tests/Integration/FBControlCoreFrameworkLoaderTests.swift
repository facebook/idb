/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import FBControlCore

final class FBControlCoreFrameworkLoaderTests: XCTestCase {

  private func assertLoadsFramework(_ framework: FBWeakFramework) {
    XCTAssertNoThrow(try framework.load(with: FBControlCoreGlobalConfiguration.defaultLogger))
  }

  func testLoadsAccessibilityPlatformTranslation() {
    assertLoadsFramework(.accessibilityPlatformTranslation)
  }

  func testLoadsCoreSimulator() {
    assertLoadsFramework(.coreSimulator)
  }

  func testLoadsDTXConnectionServices() {
    assertLoadsFramework(.dtxConnectionServices)
  }

  func testLoadsMobileDevice() {
    assertLoadsFramework(.mobileDevice)
  }

  func testLoadsSimulatorKit() {
    assertLoadsFramework(.simulatorKit)
  }

  func testLoadsXCTest() {
    assertLoadsFramework(.xcTest)
  }
}
