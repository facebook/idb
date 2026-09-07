/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

private let installTypeStringUnknown = "unknown"
private let installTypeStringSystem = "system"
private let installTypeStringMac = "mac"
private let installTypeStringUser = "user"
private let installTypeStringUserEnterprise = "user_enterprise"
private let installTypeStringUserDevelopment = "user_development"

/// How an application came to be installed.
@objc public enum FBApplicationInstallType: UInt, Sendable {
  /// The Application is unknown.
  case unknown = 0
  /// The Application is part of the Operating System.
  case system = 1
  /// The Application is part of macOS.
  case mac = 2
  /// The Application has been installed by the user.
  case user = 3
  /// The Application has been installed by the user and signed with a distribution certificate.
  case userEnterprise = 4
  /// The Application has been installed by the user and signed with a development certificate.
  case userDevelopment = 5
}

/// Keys of the application info dictionary.
public struct FBApplicationInstallInfoKey: RawRepresentable, Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let applicationType = FBApplicationInstallInfoKey(rawValue: "ApplicationType")
  public static let bundleIdentifier = FBApplicationInstallInfoKey(rawValue: "CFBundleIdentifier")
  public static let bundleName = FBApplicationInstallInfoKey(rawValue: "CFBundleName")
  public static let path = FBApplicationInstallInfoKey(rawValue: "Path")
  public static let signerIdentity = FBApplicationInstallInfoKey(rawValue: "SignerIdentity")
}

public struct FBInstalledApplication: Hashable, Sendable, CustomStringConvertible {

  public let bundle: FBBundleDescriptor
  public let installType: FBApplicationInstallType
  public let dataContainer: String?

  public var installTypeString: String {
    FBInstalledApplication.string(from: installType)
  }

  public static func installedApplication(withBundle bundle: FBBundleDescriptor, installType: FBApplicationInstallType, dataContainer: String?) -> FBInstalledApplication {
    FBInstalledApplication(bundle: bundle, installType: installType, dataContainer: dataContainer)
  }

  public static func installedApplication(withBundle bundle: FBBundleDescriptor, installTypeString: String?, signerIdentity: String?, dataContainer: String?) -> FBInstalledApplication {
    FBInstalledApplication(bundle: bundle, installTypeString: installTypeString, signerIdentity: signerIdentity, dataContainer: dataContainer)
  }

  public init(bundle: FBBundleDescriptor, installType: FBApplicationInstallType, dataContainer: String?) {
    self.bundle = bundle
    self.installType = installType
    self.dataContainer = dataContainer
  }

  public init(bundle: FBBundleDescriptor, installTypeString: String?, signerIdentity: String?, dataContainer: String?) {
    let installType = FBInstalledApplication.installType(from: installTypeString, signerIdentity: signerIdentity)
    self.init(bundle: bundle, installType: installType, dataContainer: dataContainer)
  }

  /// The data container takes part in equality but not in the hash, so two applications
  /// that differ only by their container are unequal and share a hash bucket.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(bundle.hash ^ Int(installType.rawValue))
  }

  public static func == (lhs: FBInstalledApplication, rhs: FBInstalledApplication) -> Bool {
    lhs.bundle.isEqual(rhs.bundle)
      && lhs.installType == rhs.installType
      && lhs.dataContainer == rhs.dataContainer
  }

  public var description: String {
    "Bundle \(bundle.description) | Install Type \(installTypeString) | Container \(dataContainer ?? "nil")"
  }

  // MARK: - Install Type Mapping

  public static func string(from installType: FBApplicationInstallType) -> String {
    switch installType {
    case .user: return installTypeStringUser
    case .userDevelopment: return installTypeStringUserDevelopment
    case .userEnterprise: return installTypeStringUserEnterprise
    case .system: return installTypeStringSystem
    case .mac: return installTypeStringMac
    case .unknown: return installTypeStringUnknown
    @unknown default: return installTypeStringUnknown
    }
  }

  public static func installType(from installTypeString: String?, signerIdentity: String?) -> FBApplicationInstallType {
    guard let installTypeString = installTypeString?.lowercased() else {
      return .unknown
    }
    if installTypeString == installTypeStringSystem {
      return .system
    }
    if installTypeString == installTypeStringUser {
      if let signerIdentity {
        if signerIdentity.contains("iPhone Distribution") {
          return .userEnterprise
        } else if signerIdentity.contains("iPhone Developer") || signerIdentity.contains("Apple Development") {
          return .userDevelopment
        }
      }
      return .user
    }
    if installTypeString == installTypeStringMac {
      return .mac
    }
    return .unknown
  }
}
