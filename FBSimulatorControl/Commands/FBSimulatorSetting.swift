/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A curated, device-wide simulator setting applied via `SettingsCommands.apply(_:)`.
///
/// Each case maps to a different underlying transport (a SimDevice API, a Darwin notification, or a
/// preference write), but callers build a value and hand it to a single `apply` entry point rather
/// than reaching for a method per setting. Parsing a CLI `name`/`value` — including the raw-preference
/// fallback for uncurated names — is `FBSimulatorSettingResolution`'s job.
public enum FBSimulatorSetting: Equatable {
  case hardwareKeyboard(Bool)
  case slowAnimations(Bool)
  case increaseContrast(Bool)
  case autoFillPasswords(Bool)
  case appearance(FBSimulatorAppearance)
  case contentSize(FBSimulatorContentSizeCategory)
  case locale(localeIdentifier: String)
}

/// The result of resolving a CLI `set` `name`/`value`: either a curated `FBSimulatorSetting` or a raw
/// preference write for any name that is not curated. Callers hand this to `apply(_:)`; keeping the
/// raw case out of `FBSimulatorSetting` lets that enum stay purely the curated settings.
public enum FBSimulatorSettingResolution: Equatable {
  case setting(FBSimulatorSetting)
  case preference(name: String, value: String, type: String?, domain: String?)
}

/// The curated setting names. Raw values are the CLI names and the single source of truth shared by
/// the parser (`FBSimulatorSettingResolution.init(name:...)`) and the getter (`currentSettingValue`),
/// so each setting's name is declared once and both switches stay exhaustive over it.
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
  /// For a setting whose transport is a preference write, the `(domain, key)` that both `apply` and
  /// the getter use — declared once so set and get never duplicate it. `nil` for settings backed by a
  /// SimDevice API or a Darwin notification, which have no readable preference.
  ///
  /// `autofill-passwords` maps to `com.apple.WebUI` / `AutoFillPasswords`: disabling it suppresses the
  /// native "Automatic Strong Password" cover shown over `UITextContentTypeNewPassword` fields.
  var preferenceBacking: (domain: String?, key: String)? {
    switch self {
    case .autoFillPasswords:
      return (domain: "com.apple.WebUI", key: "AutoFillPasswords")
    case .locale:
      return (domain: nil, key: "AppleLocale")
    case .hardwareKeyboard, .slowAnimations, .increaseContrast, .appearance, .contentSize:
      return nil
    }
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
  /// This is the single source of truth for the `set` surface shared by idb and sime2e.
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

  public var argumentName: String? {
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

  public var argumentName: String? {
    FBSimulatorContentSizeCategory.argumentNames.first(where: { $0.value == self })?.name
  }

  public static var allArgumentNames: [String] {
    argumentNames.map(\.name)
  }
}
