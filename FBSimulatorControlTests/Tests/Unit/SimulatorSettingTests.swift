/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

final class SimulatorSettingTests: XCTestCase {

  // MARK: - FBSimulatorSettingResolution Parsing

  func testParseHardwareKeyboardEnableDisable() throws {
    XCTAssertEqual(try FBSimulatorSettingResolution(name: "hardware-keyboard", value: "enable", type: nil, domain: nil), .setting(.hardwareKeyboard(true)))
    XCTAssertEqual(try FBSimulatorSettingResolution(name: "hardware-keyboard", value: "disable", type: nil, domain: nil), .setting(.hardwareKeyboard(false)))
  }

  func testParseSlowAnimationsAndIncreaseContrast() throws {
    XCTAssertEqual(try FBSimulatorSettingResolution(name: "slow-animations", value: "enable", type: nil, domain: nil), .setting(.slowAnimations(true)))
    XCTAssertEqual(try FBSimulatorSettingResolution(name: "increase-contrast", value: "disable", type: nil, domain: nil), .setting(.increaseContrast(false)))
  }

  func testParseInvalidEnableDisableThrows() {
    XCTAssertThrowsError(try FBSimulatorSettingResolution(name: "hardware-keyboard", value: "on", type: nil, domain: nil))
  }

  func testParseAppearance() throws {
    XCTAssertEqual(try FBSimulatorSettingResolution(name: "appearance", value: "dark", type: nil, domain: nil), .setting(.appearance(.dark)))
    XCTAssertEqual(try FBSimulatorSettingResolution(name: "appearance", value: "light", type: nil, domain: nil), .setting(.appearance(.light)))
  }

  func testParseInvalidAppearanceThrows() {
    XCTAssertThrowsError(try FBSimulatorSettingResolution(name: "appearance", value: "purple", type: nil, domain: nil))
  }

  func testParseContentSize() throws {
    XCTAssertEqual(try FBSimulatorSettingResolution(name: "content-size", value: "large", type: nil, domain: nil), .setting(.contentSize(.large)))
    XCTAssertEqual(
      try FBSimulatorSettingResolution(name: "content-size", value: "accessibility-medium", type: nil, domain: nil),
      .setting(.contentSize(.accessibilityMedium)))
  }

  func testParseInvalidContentSizeThrows() {
    XCTAssertThrowsError(try FBSimulatorSettingResolution(name: "content-size", value: "gigantic", type: nil, domain: nil))
  }

  func testParseLocale() throws {
    XCTAssertEqual(try FBSimulatorSettingResolution(name: "locale", value: "en_US", type: nil, domain: nil), .setting(.locale(localeIdentifier: "en_US")))
  }

  func testParseAutofillPasswords() throws {
    XCTAssertEqual(try FBSimulatorSettingResolution(name: "autofill-passwords", value: "disable", type: nil, domain: nil), .setting(.autoFillPasswords(false)))
    XCTAssertEqual(try FBSimulatorSettingResolution(name: "autofill-passwords", value: "enable", type: nil, domain: nil), .setting(.autoFillPasswords(true)))
    XCTAssertThrowsError(try FBSimulatorSettingResolution(name: "autofill-passwords", value: "off", type: nil, domain: nil))
  }

  func testParseUnknownNameFallsBackToPreference() throws {
    XCTAssertEqual(
      try FBSimulatorSettingResolution(name: "com.example.Key", value: "1", type: "int", domain: "com.example"),
      .preference(name: "com.example.Key", value: "1", type: "int", domain: "com.example"))
  }

  func testArgumentNameRoundTrip() {
    XCTAssertEqual(SimulatorAppearance(argumentName: "dark"), SimulatorAppearance.dark)
    XCTAssertEqual(SimulatorAppearance.dark.argumentName, "dark")
    XCTAssertEqual(FBSimulatorContentSizeCategory(argumentName: "large"), FBSimulatorContentSizeCategory.large)
    XCTAssertEqual(FBSimulatorContentSizeCategory.large.argumentName, "large")
    XCTAssertNil(SimulatorAppearance(argumentName: "purple"))
  }

  func testPreferenceBacking() {
    // nil domain == Apple Global Domain, where the native AutoFill Passwords toggle lives.
    XCTAssertNil(SimulatorSettingKey.autoFillPasswords.preferenceBacking?.domain)
    XCTAssertEqual(SimulatorSettingKey.autoFillPasswords.preferenceBacking?.key, "AutoFillPasswords")
    XCTAssertNil(SimulatorSettingKey.locale.preferenceBacking?.domain)
    XCTAssertEqual(SimulatorSettingKey.locale.preferenceBacking?.key, "AppleLocale")
    XCTAssertNil(SimulatorSettingKey.hardwareKeyboard.preferenceBacking)
    XCTAssertNil(SimulatorSettingKey.appearance.preferenceBacking)
  }

  func testWeakTargetErrorMessage() {
    XCTAssertEqual(FBWeakTargetError.deallocated("Simulator").errorDescription, "Simulator deallocated")
    XCTAssertEqual(FBWeakTargetError.simulator.errorDescription, "Simulator deallocated")
  }

  func testCuratedNames() {
    XCTAssertEqual(FBSimulatorSetting.curatedNames, SimulatorSettingKey.allCases.map(\.rawValue))
    XCTAssertTrue(FBSimulatorSetting.curatedNames.contains("autofill-passwords"))
    XCTAssertTrue(FBSimulatorSetting.curatedNames.contains("appearance"))
    XCTAssertFalse(FBSimulatorSetting.curatedNames.contains("com.example.Key"))
  }
}
