/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

/// Dark/Light mode appearance.
/// Values match UIUserInterfaceStyle used by SimDevice's setUIInterfaceStyle:error:.
public enum SimulatorAppearance: Int, Sendable {
  case light = 1 // UIUserInterfaceStyleLight
  case dark = 2 // UIUserInterfaceStyleDark
}

/// Dynamic Type content size categories.
/// Values match the integer indices used by SimDevice's setContentSizeCategory:error:.
public enum SimulatorContentSizeCategory: Int, Sendable {
  case extraSmall = 1
  case small = 2
  case medium = 3
  case large = 4
  case extraLarge = 5
  case extraExtraLarge = 6
  case extraExtraExtraLarge = 7
  case accessibilityMedium = 8
  case accessibilityLarge = 9
  case accessibilityExtraLarge = 10
  case accessibilityExtraExtraLarge = 11
  case accessibilityExtraExtraExtraLarge = 12
}

enum SimulatorIncreaseContrastMode: Int {
  case disabled = 1
  case enabled = 2
}

private let slowAnimationsNotification = "com.apple.UIKit.SimulatorSlowMotionAnimationState"

public enum SimulatorPreferencesError: Error, LocalizedError {
  case settingNotPreferenceBacked(setting: String)
  case accessibilitySettingsReadbackMismatch(setting: String, expected: Bool, actual: Bool)
  case unexpectedAppearance(Int)
  case unexpectedContentSizeCategory(Int)
  case unexpectedIncreaseContrastMode(Int)

  public var errorDescription: String? {
    switch self {
    case let .settingNotPreferenceBacked(setting):
      return "Setting '\(setting)' is not backed by a preference"
    case let .accessibilitySettingsReadbackMismatch(setting, expected, actual):
      return "The simulator reported \(setting)=\(actual) after \(expected) was requested"
    case let .unexpectedAppearance(appearance):
      return "The simulator returned an unknown appearance value: \(appearance)"
    case let .unexpectedContentSizeCategory(category):
      return "The simulator returned an unknown content size category: \(category)"
    case let .unexpectedIncreaseContrastMode(mode):
      return "The simulator returned an unknown Increase Contrast mode: \(mode)"
    }
  }
}

/// Reads and writes the simulated device's settings, both the curated ones and raw preferences.
public struct SimulatorPreferencesCommands {

  private let simulator: FBSimulator

  // MARK: - Initializers

  public static func commands(with simulator: FBSimulator) -> SimulatorPreferencesCommands {
    SimulatorPreferencesCommands(simulator: simulator)
  }

  internal init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  // MARK: - Applying

  public func apply(_ setting: FBSimulatorSetting) async throws {
    switch setting {
    case let .hardwareKeyboard(enabled):
      try await setHardwareKeyboardEnabled(enabled)
    case let .slowAnimations(enabled):
      try await setSlowAnimationsEnabled(enabled)
    case let .increaseContrast(enabled):
      try await setIncreaseContrastEnabled(enabled)
    case let .reduceMotion(enabled):
      try await setAccessibilitySetting(.reduceMotion, enabled: enabled)
    case let .reduceTransparency(enabled):
      try await setAccessibilitySetting(.reduceTransparency, enabled: enabled)
    case let .buttonShapes(enabled):
      try await setAccessibilitySetting(.buttonShapes, enabled: enabled)
    case let .voiceOver(enabled):
      try await setAccessibilitySetting(.voiceOver, enabled: enabled)
    case let .autoFillPasswords(enabled):
      try await setPreferenceBacked(.autoFillPasswords, value: enabled ? "true" : "false", type: "bool")
    case let .appearance(appearance):
      try await setAppearance(appearance)
    case let .contentSize(category):
      try await setContentSizeCategory(category)
    case let .locale(localeIdentifier):
      try await setPreferenceBacked(.locale, value: localeIdentifier, type: nil)
    }
  }

  public func apply(_ resolution: FBSimulatorSettingResolution) async throws {
    switch resolution {
    case let .setting(setting):
      try await apply(setting)
    case let .preference(name, value, type, domain):
      try await setPreference(name, value: value, type: type, domain: domain)
    }
  }

  // MARK: - Reading

  public func getCurrentPreference(_ name: String, domain: String?) async throws -> String {
    try await PreferenceModificationStrategy(simulator: simulator)
      .getCurrentPreference(name, domain: domain)
  }

  /// Reads the current value of a curated setting by name, falling back to a raw preference read for
  /// any other name.
  public func currentSettingValue(name: String, domain: String?) async throws -> String {
    guard let key = SimulatorSettingKey(rawValue: name) else {
      return try await getCurrentPreference(name, domain: domain)
    }
    switch key {
    case .autoFillPasswords, .locale:
      guard let backing = key.preferenceBacking else {
        return try await getCurrentPreference(name, domain: domain)
      }
      return try await getCurrentPreference(backing.key, domain: backing.domain)
    case .appearance:
      return (try await currentAppearance()).argumentName ?? "light"
    case .contentSize:
      return (try await currentContentSizeCategory()).argumentName ?? "large"
    case .increaseContrast:
      return try currentIncreaseContrastEnabled() ? "enabled" : "disabled"
    case .reduceMotion, .reduceTransparency, .buttonShapes, .voiceOver:
      return try await currentAccessibilitySettingEnabled(key) ? "enabled" : "disabled"
    case .hardwareKeyboard, .slowAnimations:
      // Set-only (SimDevice API / Darwin notification with no getter); no readable current value.
      return try await getCurrentPreference(name, domain: domain)
    }
  }

  // MARK: - Private

  static func appearance(rawValue: Int) throws -> SimulatorAppearance {
    guard let appearance = SimulatorAppearance(rawValue: rawValue) else {
      throw SimulatorPreferencesError.unexpectedAppearance(rawValue)
    }
    return appearance
  }

  static func contentSizeCategory(rawValue: Int) throws -> SimulatorContentSizeCategory {
    guard let category = SimulatorContentSizeCategory(rawValue: rawValue) else {
      throw SimulatorPreferencesError.unexpectedContentSizeCategory(rawValue)
    }
    return category
  }

  private func currentAppearance() async throws -> SimulatorAppearance {
    try Self.appearance(rawValue: simulator.device.currentUIInterfaceStyle())
  }

  private func setAppearance(_ appearance: SimulatorAppearance) async throws {
    try simulator.device.setUIInterfaceStyle(appearance.rawValue)
  }

  private func currentContentSizeCategory() async throws -> SimulatorContentSizeCategory {
    try Self.contentSizeCategory(rawValue: simulator.device.currentContentSizeCategory())
  }

  private func setContentSizeCategory(_ category: SimulatorContentSizeCategory) async throws {
    try simulator.device.setContentSizeCategory(category.rawValue)
  }

  private func setHardwareKeyboardEnabled(_ enabled: Bool) async throws {
    try simulator.device.setHardwareKeyboardEnabled(enabled, keyboardType: 0)
  }

  private func setSlowAnimationsEnabled(_ enabled: Bool) async throws {
    try await setDarwinNotificationState(enabled, name: slowAnimationsNotification)
  }

  private func currentAccessibilitySettingEnabled(_ key: SimulatorSettingKey) async throws -> Bool {
    guard let settingName = key.accessibilityBridgeName else {
      throw SimulatorPreferencesError.settingNotPreferenceBacked(setting: key.rawValue)
    }
    let data = try await AXBridgeOneshotTransport(simulator: simulator)
      .send(.deviceSettingRead(settingName))
    return try AXDeviceSettingResponse(data: data).enabled
  }

  private func setAccessibilitySetting(_ key: SimulatorSettingKey, enabled: Bool) async throws {
    guard let settingName = key.accessibilityBridgeName else {
      throw SimulatorPreferencesError.settingNotPreferenceBacked(setting: key.rawValue)
    }
    let data = try await AXBridgeOneshotTransport(simulator: simulator)
      .send(.deviceSettingWrite(settingName, enabled: enabled))
    let actual = try AXDeviceSettingResponse(data: data).enabled
    guard actual == enabled else {
      throw SimulatorPreferencesError.accessibilitySettingsReadbackMismatch(
        setting: settingName,
        expected: enabled,
        actual: actual)
    }
  }

  private func currentIncreaseContrastEnabled() throws -> Bool {
    let rawMode = simulator.device.currentIncreaseContrastMode()
    guard let mode = SimulatorIncreaseContrastMode(rawValue: rawMode) else {
      throw SimulatorPreferencesError.unexpectedIncreaseContrastMode(rawMode)
    }
    return mode == .enabled
  }

  private func setIncreaseContrastEnabled(_ enabled: Bool) async throws {
    try simulator.device.setIncreaseContrastEnabled(enabled)
  }

  private func setPreferenceBacked(_ key: SimulatorSettingKey, value: String, type: String?) async throws {
    guard let backing = key.preferenceBacking else {
      throw SimulatorPreferencesError.settingNotPreferenceBacked(setting: key.rawValue)
    }
    try await setPreference(backing.key, value: value, type: type, domain: backing.domain)
  }

  private func setDarwinNotificationState(_ enabled: Bool, name: String) async throws {
    try simulator.device.darwinNotificationSetState(enabled ? 1 : 0, name: name)
    try simulator.device.postDarwinNotification(name)
  }

  private func setPreference(_ name: String, value: String, type: String?, domain: String?) async throws {
    try await PreferenceModificationStrategy(simulator: simulator)
      .setPreference(name, value: value, type: type, domain: domain)
  }
}
