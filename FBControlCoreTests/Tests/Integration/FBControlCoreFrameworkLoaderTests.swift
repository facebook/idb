/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

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

  // `FBControlCoreFrameworkLoader` declares its `logger:` parameter nullable and forwards it here
  // unchanged, so a process that never configured a logger reaches this API with nil.
  func testLoadsWithoutALogger() {
    XCTAssertNoThrow(try FBWeakFramework.coreSimulator.load(with: nil))
  }
}
