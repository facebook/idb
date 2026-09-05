/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A curated, device-wide simulator setting applied via `SettingsCommands.apply(_:)`. Parsing a CLI
/// `name`/`value` is `FBSimulatorSettingResolution`'s job.
public enum FBSimulatorSetting: Equatable {
  case hardwareKeyboard(Bool)
  case slowAnimations(Bool)
  case increaseContrast(Bool)
  case autoFillPasswords(Bool)
  case appearance(FBSimulatorAppearance)
  case contentSize(FBSimulatorContentSizeCategory)
  case locale(localeIdentifier: String)
}

/// The result of resolving a CLI `set` `name`/`value`: a curated `FBSimulatorSetting`, or a raw
/// preference write for any other name.
public enum FBSimulatorSettingResolution: Equatable {
  case setting(FBSimulatorSetting)
  case preference(name: String, value: String, type: String?, domain: String?)
}

/// The curated setting names; raw values are the CLI names.
enum FBSimulatorSettingKey: String, CaseIterable {
  case hardwareKeyboard = "hardware-keyboard"
  case slowAnimations = "slow-animations"
  case increaseContrast = "increase-contrast"
  case autoFillPasswords = "autofill-passwords"
  case appearance
  case contentSize = "content-size"
  case locale
}

extension FBSimulatorSettingKey {
  /// The `(domain, key)` for a preference-backed setting; `nil` for settings with no readable
  /// preference (SimDevice API or Darwin notification).
  ///
  /// `autofill-passwords` maps to the Apple Global Domain `AutoFillPasswords` toggle: disabling it
  /// suppresses the native "Automatic Strong Password" cover shown over `UITextContentTypeNewPassword`
  /// fields. Writing `com.apple.WebUI` instead only affects WebKit and does not suppress the native
  /// cover on iOS 26.2+.
  var preferenceBacking: (domain: String?, key: String)? {
    switch self {
    case .autoFillPasswords:
      return (domain: nil, key: "AutoFillPasswords")
    case .locale:
      return (domain: nil, key: "AppleLocale")
    case .hardwareKeyboard, .slowAnimations, .increaseContrast, .appearance, .contentSize:
      return nil
    }
  }
}

public extension FBSimulatorSetting {
  /// The curated setting names accepted by `set`/`get`. A name outside this list is treated as a raw
  /// preference key. Useful for rendering CLI help and discoverability.
  static var curatedNames: [String] {
    FBSimulatorSettingKey.allCases.map(\.rawValue)
  }
}

/// Raised when a `name`/`value` pair cannot be parsed into an `FBSimulatorSetting`.
public enum FBSimulatorSettingError: Error, CustomStringConvertible, LocalizedError {
  case invalidValue(name: String, value: String, expected: String)

  public var description: String {
    switch self {
    case let .invalidValue(name, value, expected):
      return "Invalid \(name) value '\(value)'. Expected one of: \(expected)"
    }
  }

  public var errorDescription: String? { description }
}

extension FBSimulatorSettingResolution {

  /// Parse a CLI-style `name`/`value` into a resolution. A curated name yields `.setting`; any other
  /// name yields `.preference` (a raw defaults write), the only case that consults `type`/`domain`.
  public init(name: String, value: String, type: String?, domain: String?) throws {
    guard let key = FBSimulatorSettingKey(rawValue: name) else {
      self = .preference(name: name, value: value, type: type, domain: domain)
      return
    }
    switch key {
    case .hardwareKeyboard:
      self = .setting(.hardwareKeyboard(try FBSimulatorSettingResolution.parseEnabled(name: name, value: value)))
    case .slowAnimations:
      self = .setting(.slowAnimations(try FBSimulatorSettingResolution.parseEnabled(name: name, value: value)))
    case .increaseContrast:
      self = .setting(.increaseContrast(try FBSimulatorSettingResolution.parseEnabled(name: name, value: value)))
    case .autoFillPasswords:
      self = .setting(.autoFillPasswords(try FBSimulatorSettingResolution.parseEnabled(name: name, value: value)))
    case .appearance:
      guard let appearance = FBSimulatorAppearance(argumentName: value) else {
        throw FBSimulatorSettingError.invalidValue(
          name: name, value: value, expected: FBSimulatorAppearance.allArgumentNames.joined(separator: ", "))
      }
      self = .setting(.appearance(appearance))
    case .contentSize:
      guard let category = FBSimulatorContentSizeCategory(argumentName: value) else {
        throw FBSimulatorSettingError.invalidValue(
          name: name, value: value, expected: FBSimulatorContentSizeCategory.allArgumentNames.joined(separator: ", "))
      }
      self = .setting(.contentSize(category))
    case .locale:
      self = .setting(.locale(localeIdentifier: value))
    }
  }

  private static func parseEnabled(name: String, value: String) throws -> Bool {
    switch value {
    case "enable":
      return true
    case "disable":
      return false
    default:
      throw FBSimulatorSettingError.invalidValue(name: name, value: value, expected: "enable, disable")
    }
  }
}

// MARK: - Argument name mappings

extension FBSimulatorAppearance {
  private static let argumentNames: [(name: String, value: FBSimulatorAppearance)] = [
    ("dark", .dark),
    ("light", .light),
  ]

  public init?(argumentName: String) {
    guard let entry = FBSimulatorAppearance.argumentNames.first(where: { $0.name == argumentName }) else {
      return nil
    }
    self = entry.value
  }

  var argumentName: String? {
    FBSimulatorAppearance.argumentNames.first(where: { $0.value == self })?.name
  }

  public static var allArgumentNames: [String] {
    argumentNames.map(\.name)
  }
}

extension FBSimulatorContentSizeCategory {
  private static let argumentNames: [(name: String, value: FBSimulatorContentSizeCategory)] = [
    ("extra-small", .extraSmall),
    ("small", .small),
    ("medium", .medium),
    ("large", .large),
    ("extra-large", .extraLarge),
    ("extra-extra-large", .extraExtraLarge),
    ("extra-extra-extra-large", .extraExtraExtraLarge),
    ("accessibility-medium", .accessibilityMedium),
    ("accessibility-large", .accessibilityLarge),
    ("accessibility-extra-large", .accessibilityExtraLarge),
    ("accessibility-extra-extra-large", .accessibilityExtraExtraLarge),
    ("accessibility-extra-extra-extra-large", .accessibilityExtraExtraExtraLarge),
  ]

  public init?(argumentName: String) {
    guard let entry = FBSimulatorContentSizeCategory.argumentNames.first(where: { $0.name == argumentName }) else {
      return nil
    }
    self = entry.value
  }

  var argumentName: String? {
    FBSimulatorContentSizeCategory.argumentNames.first(where: { $0.value == self })?.name
  }

  public static var allArgumentNames: [String] {
    argumentNames.map(\.name)
  }
}
