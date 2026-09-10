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
public enum FBSimulatorContentSizeCategory: Int, Sendable {
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

private let slowAnimationsNotification = "com.apple.UIKit.SimulatorSlowMotionAnimationState"

public enum SimulatorPreferencesError: Error, LocalizedError {
  case settingNotPreferenceBacked(setting: String)

  public var errorDescription: String? {
    switch self {
    case let .settingNotPreferenceBacked(setting):
      return "Setting '\(setting)' is not backed by a preference"
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
    case .hardwareKeyboard, .slowAnimations, .increaseContrast:
      // Set-only (SimDevice API / Darwin notification with no getter); no readable current value.
      return try await getCurrentPreference(name, domain: domain)
    }
  }

  // MARK: - Private

  private func currentAppearance() async throws -> SimulatorAppearance {
    let raw = simulator.device.currentUIInterfaceStyle()
    return SimulatorAppearance(rawValue: raw) ?? .light
  }

  private func setAppearance(_ appearance: SimulatorAppearance) async throws {
    try simulator.device.setUIInterfaceStyle(appearance.rawValue)
  }

  private func currentContentSizeCategory() async throws -> FBSimulatorContentSizeCategory {
    let raw = simulator.device.currentContentSizeCategory()
    return FBSimulatorContentSizeCategory(rawValue: raw) ?? .large
  }

  private func setContentSizeCategory(_ category: FBSimulatorContentSizeCategory) async throws {
    try simulator.device.setContentSizeCategory(category.rawValue)
  }

  private func setHardwareKeyboardEnabled(_ enabled: Bool) async throws {
    try simulator.device.setHardwareKeyboardEnabled(enabled, keyboardType: 0)
  }

  private func setSlowAnimationsEnabled(_ enabled: Bool) async throws {
    try await setDarwinNotificationState(enabled, name: slowAnimationsNotification)
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
