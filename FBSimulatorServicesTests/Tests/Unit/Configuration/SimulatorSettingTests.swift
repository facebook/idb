/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
@testable import FBSimulatorServices
import Foundation
import Testing

@Suite
struct SimulatorSettingTests {

  // MARK: - SimulatorSettingResolution Parsing

  @Test
  func parseHardwareKeyboardEnableDisable() throws {
    #expect(try SimulatorSettingResolution(name: "hardware-keyboard", value: "enable", type: nil, domain: nil) == .setting(.hardwareKeyboard(true)))
    #expect(try SimulatorSettingResolution(name: "hardware-keyboard", value: "disable", type: nil, domain: nil) == .setting(.hardwareKeyboard(false)))
  }

  @Test
  func parseSlowAnimationsAndIncreaseContrast() throws {
    #expect(try SimulatorSettingResolution(name: "slow-animations", value: "enable", type: nil, domain: nil) == .setting(.slowAnimations(true)))
    #expect(try SimulatorSettingResolution(name: "increase-contrast", value: "disable", type: nil, domain: nil) == .setting(.increaseContrast(false)))
  }

  @Test
  func parseAccessibilitySettings() throws {
    #expect(try SimulatorSettingResolution(name: "reduce-motion", value: "enable", type: nil, domain: nil) == .setting(.reduceMotion(true)))
    #expect(try SimulatorSettingResolution(name: "reduce-transparency", value: "enable", type: nil, domain: nil) == .setting(.reduceTransparency(true)))
    #expect(try SimulatorSettingResolution(name: "button-shapes", value: "disable", type: nil, domain: nil) == .setting(.buttonShapes(false)))
    #expect(try SimulatorSettingResolution(name: "voiceover", value: "disable", type: nil, domain: nil) == .setting(.voiceOver(false)))
  }

  @Test
  func parseInvalidEnableDisableThrows() {
    #expect(throws: (any Error).self) { try SimulatorSettingResolution(name: "hardware-keyboard", value: "on", type: nil, domain: nil) }
  }

  @Test
  func parseAppearance() throws {
    #expect(try SimulatorSettingResolution(name: "appearance", value: "dark", type: nil, domain: nil) == .setting(.appearance(.dark)))
    #expect(try SimulatorSettingResolution(name: "appearance", value: "light", type: nil, domain: nil) == .setting(.appearance(.light)))
  }

  @Test
  func parseInvalidAppearanceThrows() {
    #expect(throws: (any Error).self) { try SimulatorSettingResolution(name: "appearance", value: "purple", type: nil, domain: nil) }
  }

  @Test
  func parseContentSize() throws {
    #expect(try SimulatorSettingResolution(name: "content-size", value: "large", type: nil, domain: nil) == .setting(.contentSize(.large)))
    #expect(try SimulatorSettingResolution(name: "content-size", value: "accessibility-medium", type: nil, domain: nil) == .setting(.contentSize(.accessibilityMedium)))
  }

  @Test
  func parseInvalidContentSizeThrows() {
    #expect(throws: (any Error).self) { try SimulatorSettingResolution(name: "content-size", value: "gigantic", type: nil, domain: nil) }
  }

  @Test
  func parseLocale() throws {
    #expect(try SimulatorSettingResolution(name: "locale", value: "en_US", type: nil, domain: nil) == .setting(.locale(localeIdentifier: "en_US")))
  }

  @Test
  func parseAutofillPasswords() throws {
    #expect(try SimulatorSettingResolution(name: "autofill-passwords", value: "disable", type: nil, domain: nil) == .setting(.autoFillPasswords(false)))
    #expect(try SimulatorSettingResolution(name: "autofill-passwords", value: "enable", type: nil, domain: nil) == .setting(.autoFillPasswords(true)))
    #expect(throws: (any Error).self) { try SimulatorSettingResolution(name: "autofill-passwords", value: "off", type: nil, domain: nil) }
  }

  @Test
  func parseUnknownNameFallsBackToPreference() throws {
    #expect(try SimulatorSettingResolution(name: "com.example.Key", value: "1", type: "int", domain: "com.example") == .preference(name: "com.example.Key", value: "1", type: "int", domain: "com.example"))
  }

  @Test
  func argumentNameRoundTrip() {
    #expect(SimulatorAppearance(argumentName: "dark") == SimulatorAppearance.dark)
    #expect(SimulatorAppearance.dark.argumentName == "dark")
    #expect(SimulatorContentSizeCategory(argumentName: "large") == SimulatorContentSizeCategory.large)
    #expect(SimulatorContentSizeCategory.large.argumentName == "large")
    #expect(SimulatorAppearance(argumentName: "purple") == nil)
  }

  @Test
  func unknownCoreSimulatorSettingValuesThrow() throws {
    #expect(try SimulatorPreferencesCommands.appearance(rawValue: 1) == .light)
    #expect(throws: (any Error).self) { try SimulatorPreferencesCommands.appearance(rawValue: 0) }
    #expect(try SimulatorPreferencesCommands.contentSizeCategory(rawValue: 4) == .large)
    #expect(throws: (any Error).self) { try SimulatorPreferencesCommands.contentSizeCategory(rawValue: 0) }
  }

  @Test
  func increaseContrastModeValues() {
    #expect(SimulatorIncreaseContrastMode(rawValue: 1) == .disabled)
    #expect(SimulatorIncreaseContrastMode(rawValue: 2) == .enabled)
    #expect(SimulatorIncreaseContrastMode(rawValue: 0) == nil)
  }

  @Test
  func preferenceBacking() {
    // nil domain == Apple Global Domain, where the native AutoFill Passwords toggle lives.
    #expect(SimulatorSettingKey.autoFillPasswords.preferenceBacking?.domain == nil)
    #expect(SimulatorSettingKey.autoFillPasswords.preferenceBacking?.key == "AutoFillPasswords")
    #expect(SimulatorSettingKey.locale.preferenceBacking?.domain == nil)
    #expect(SimulatorSettingKey.locale.preferenceBacking?.key == "AppleLocale")
    #expect(SimulatorSettingKey.hardwareKeyboard.preferenceBacking == nil)
    #expect(SimulatorSettingKey.appearance.preferenceBacking == nil)
    #expect(SimulatorSettingKey.reduceMotion.accessibilityBridgeName == "reduce-motion")
    #expect(SimulatorSettingKey.reduceTransparency.accessibilityBridgeName == "reduce-transparency")
    #expect(SimulatorSettingKey.buttonShapes.accessibilityBridgeName == "button-shapes")
    #expect(SimulatorSettingKey.voiceOver.accessibilityBridgeName == "voiceover")
    #expect(SimulatorSettingKey.increaseContrast.accessibilityBridgeName == nil)
  }

  @Test
  func weakTargetErrorMessage() {
    #expect(WeakTargetError.deallocated("Simulator").errorDescription == "Simulator deallocated")
    #expect(WeakTargetError.simulator.errorDescription == "Simulator deallocated")
  }

  @Test
  func curatedNames() {
    #expect(SimulatorSetting.curatedNames == SimulatorSettingKey.allCases.map(\.rawValue))
    #expect(SimulatorSetting.curatedNames.contains("autofill-passwords"))
    #expect(SimulatorSetting.curatedNames.contains("appearance"))
    #expect(!SimulatorSetting.curatedNames.contains("com.example.Key"))
  }
}
