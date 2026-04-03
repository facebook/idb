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

@objc(FBInstalledApplication)
public final class FBInstalledApplication: NSObject, NSCopying {

  @objc public let bundle: FBBundleDescriptor
  @objc public let installType: FBApplicationInstallType
  @objc public let dataContainer: String?

  @objc public var installTypeString: String {
    return FBInstalledApplication.string(from: installType)
  }

  @objc(installedApplicationWithBundle:installType:dataContainer:)
  public class func installedApplication(withBundle bundle: FBBundleDescriptor, installType: FBApplicationInstallType, dataContainer: String?) -> FBInstalledApplication {
    return FBInstalledApplication(bundle: bundle, installType: installType, dataContainer: dataContainer)
  }

  @objc(installedApplicationWithBundle:installTypeString:signerIdentity:dataContainer:)
  public class func installedApplication(withBundle bundle: FBBundleDescriptor, installTypeString: String?, signerIdentity: String?, dataContainer: String?) -> FBInstalledApplication {
    let installType = FBInstalledApplication.installType(from: installTypeString, signerIdentity: signerIdentity)
    return FBInstalledApplication(bundle: bundle, installType: installType, dataContainer: dataContainer)
  }

  @objc
  public init(bundle: FBBundleDescriptor, installType: FBApplicationInstallType, dataContainer: String?) {
    self.bundle = bundle
    self.installType = installType
    self.dataContainer = dataContainer
    super.init()
  }

  @objc
  public convenience init(bundle: FBBundleDescriptor, installTypeString: String?, signerIdentity: String?, dataContainer: String?) {
    let installType = FBInstalledApplication.installType(from: installTypeString, signerIdentity: signerIdentity)
    self.init(bundle: bundle, installType: installType, dataContainer: dataContainer)
  }

  // MARK: NSObject

  public override var hash: Int {
    return bundle.hash ^ Int(installType.rawValue)
  }

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBInstalledApplication else { return false }
    return bundle.isEqual(other.bundle)
      && installType == other.installType
      && dataContainer == other.dataContainer
  }

  public override var description: String {
    return "Bundle \(bundle.description) | Install Type \(installTypeString) | Container \(dataContainer ?? "nil")"
  }

  // MARK: NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    return self
  }

  // MARK: Private

  @objc(stringFromApplicationInstallType:)
  public class func string(from installType: FBApplicationInstallType) -> String {
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

  @objc(installTypeFromString:signerIdentity:)
  public class func installType(from installTypeString: String?, signerIdentity: String?) -> FBApplicationInstallType {
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
