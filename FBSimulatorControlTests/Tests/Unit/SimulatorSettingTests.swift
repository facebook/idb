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

  // MARK: - SimulatorSettingResolution Parsing

  func testParseHardwareKeyboardEnableDisable() throws {
    XCTAssertEqual(try SimulatorSettingResolution(name: "hardware-keyboard", value: "enable", type: nil, domain: nil), .setting(.hardwareKeyboard(true)))
    XCTAssertEqual(try SimulatorSettingResolution(name: "hardware-keyboard", value: "disable", type: nil, domain: nil), .setting(.hardwareKeyboard(false)))
  }

  func testParseSlowAnimationsAndIncreaseContrast() throws {
    XCTAssertEqual(try SimulatorSettingResolution(name: "slow-animations", value: "enable", type: nil, domain: nil), .setting(.slowAnimations(true)))
    XCTAssertEqual(try SimulatorSettingResolution(name: "increase-contrast", value: "disable", type: nil, domain: nil), .setting(.increaseContrast(false)))
  }

  func testParseAccessibilitySettings() throws {
    XCTAssertEqual(
      try SimulatorSettingResolution(name: "reduce-motion", value: "enable", type: nil, domain: nil),
      .setting(.reduceMotion(true)))
    XCTAssertEqual(
      try SimulatorSettingResolution(name: "reduce-transparency", value: "enable", type: nil, domain: nil),
      .setting(.reduceTransparency(true)))
    XCTAssertEqual(
      try SimulatorSettingResolution(name: "button-shapes", value: "disable", type: nil, domain: nil),
      .setting(.buttonShapes(false)))
    XCTAssertEqual(
      try SimulatorSettingResolution(name: "voiceover", value: "disable", type: nil, domain: nil),
      .setting(.voiceOver(false)))
  }

  func testParseInvalidEnableDisableThrows() {
    XCTAssertThrowsError(try SimulatorSettingResolution(name: "hardware-keyboard", value: "on", type: nil, domain: nil))
  }

  func testParseAppearance() throws {
    XCTAssertEqual(try SimulatorSettingResolution(name: "appearance", value: "dark", type: nil, domain: nil), .setting(.appearance(.dark)))
    XCTAssertEqual(try SimulatorSettingResolution(name: "appearance", value: "light", type: nil, domain: nil), .setting(.appearance(.light)))
  }

  func testParseInvalidAppearanceThrows() {
    XCTAssertThrowsError(try SimulatorSettingResolution(name: "appearance", value: "purple", type: nil, domain: nil))
  }

  func testParseContentSize() throws {
    XCTAssertEqual(try SimulatorSettingResolution(name: "content-size", value: "large", type: nil, domain: nil), .setting(.contentSize(.large)))
    XCTAssertEqual(
      try SimulatorSettingResolution(name: "content-size", value: "accessibility-medium", type: nil, domain: nil),
      .setting(.contentSize(.accessibilityMedium)))
  }

  func testParseInvalidContentSizeThrows() {
    XCTAssertThrowsError(try SimulatorSettingResolution(name: "content-size", value: "gigantic", type: nil, domain: nil))
  }

  func testParseLocale() throws {
    XCTAssertEqual(try SimulatorSettingResolution(name: "locale", value: "en_US", type: nil, domain: nil), .setting(.locale(localeIdentifier: "en_US")))
  }

  func testParseAutofillPasswords() throws {
    XCTAssertEqual(try SimulatorSettingResolution(name: "autofill-passwords", value: "disable", type: nil, domain: nil), .setting(.autoFillPasswords(false)))
    XCTAssertEqual(try SimulatorSettingResolution(name: "autofill-passwords", value: "enable", type: nil, domain: nil), .setting(.autoFillPasswords(true)))
    XCTAssertThrowsError(try SimulatorSettingResolution(name: "autofill-passwords", value: "off", type: nil, domain: nil))
  }

  func testParseUnknownNameFallsBackToPreference() throws {
    XCTAssertEqual(
      try SimulatorSettingResolution(name: "com.example.Key", value: "1", type: "int", domain: "com.example"),
      .preference(name: "com.example.Key", value: "1", type: "int", domain: "com.example"))
  }

  func testArgumentNameRoundTrip() {
    XCTAssertEqual(SimulatorAppearance(argumentName: "dark"), SimulatorAppearance.dark)
    XCTAssertEqual(SimulatorAppearance.dark.argumentName, "dark")
    XCTAssertEqual(SimulatorContentSizeCategory(argumentName: "large"), SimulatorContentSizeCategory.large)
    XCTAssertEqual(SimulatorContentSizeCategory.large.argumentName, "large")
    XCTAssertNil(SimulatorAppearance(argumentName: "purple"))
  }

  func testUnknownCoreSimulatorSettingValuesThrow() throws {
    XCTAssertEqual(try SimulatorPreferencesCommands.appearance(rawValue: 1), .light)
    XCTAssertThrowsError(try SimulatorPreferencesCommands.appearance(rawValue: 0))
    XCTAssertEqual(try SimulatorPreferencesCommands.contentSizeCategory(rawValue: 4), .large)
    XCTAssertThrowsError(try SimulatorPreferencesCommands.contentSizeCategory(rawValue: 0))
  }

  func testIncreaseContrastModeValues() {
    XCTAssertEqual(SimulatorIncreaseContrastMode(rawValue: 1), .disabled)
    XCTAssertEqual(SimulatorIncreaseContrastMode(rawValue: 2), .enabled)
    XCTAssertNil(SimulatorIncreaseContrastMode(rawValue: 0))
  }

  func testPreferenceBacking() {
    // nil domain == Apple Global Domain, where the native AutoFill Passwords toggle lives.
    XCTAssertNil(SimulatorSettingKey.autoFillPasswords.preferenceBacking?.domain)
    XCTAssertEqual(SimulatorSettingKey.autoFillPasswords.preferenceBacking?.key, "AutoFillPasswords")
    XCTAssertNil(SimulatorSettingKey.locale.preferenceBacking?.domain)
    XCTAssertEqual(SimulatorSettingKey.locale.preferenceBacking?.key, "AppleLocale")
    XCTAssertNil(SimulatorSettingKey.hardwareKeyboard.preferenceBacking)
    XCTAssertNil(SimulatorSettingKey.appearance.preferenceBacking)
    XCTAssertEqual(SimulatorSettingKey.reduceMotion.accessibilityBridgeName, "reduce-motion")
    XCTAssertEqual(SimulatorSettingKey.reduceTransparency.accessibilityBridgeName, "reduce-transparency")
    XCTAssertEqual(SimulatorSettingKey.buttonShapes.accessibilityBridgeName, "button-shapes")
    XCTAssertEqual(SimulatorSettingKey.voiceOver.accessibilityBridgeName, "voiceover")
    XCTAssertNil(SimulatorSettingKey.increaseContrast.accessibilityBridgeName)
  }

  func testWeakTargetErrorMessage() {
    XCTAssertEqual(WeakTargetError.deallocated("Simulator").errorDescription, "Simulator deallocated")
    XCTAssertEqual(WeakTargetError.simulator.errorDescription, "Simulator deallocated")
  }

  func testCuratedNames() {
    XCTAssertEqual(SimulatorSetting.curatedNames, SimulatorSettingKey.allCases.map(\.rawValue))
    XCTAssertTrue(SimulatorSetting.curatedNames.contains("autofill-passwords"))
    XCTAssertTrue(SimulatorSetting.curatedNames.contains("appearance"))
    XCTAssertFalse(SimulatorSetting.curatedNames.contains("com.example.Key"))
  }
}
