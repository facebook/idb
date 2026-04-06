/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// MARK: - FBiOSTargetScreenInfo

@objc(FBiOSTargetScreenInfo)
public final class FBiOSTargetScreenInfo: NSObject, NSCopying {

  @objc public let widthPixels: UInt
  @objc public let heightPixels: UInt
  @objc public let scale: Float

  @objc
  public init(widthPixels: UInt, heightPixels: UInt, scale: Float) {
    self.widthPixels = widthPixels
    self.heightPixels = heightPixels
    self.scale = scale
    super.init()
  }

  // MARK: NSObject

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBiOSTargetScreenInfo else { return false }
    return widthPixels == other.widthPixels
      && heightPixels == other.heightPixels
      && scale == other.scale
  }

  public override var hash: Int {
    return Int(widthPixels) ^ Int(heightPixels) ^ Int(scale)
  }

  public override var description: String {
    return String(format: "Screen Pixels %lu,%lu | Scale %fX", widthPixels, heightPixels, scale)
  }

  // MARK: NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    return self
  }
}

// MARK: - FBDeviceType

@objc(FBDeviceType)
public final class FBDeviceType: NSObject, NSCopying {

  @objc public let model: FBDeviceModel
  @objc public let productTypes: Set<String>
  @objc public let deviceArchitecture: FBArchitecture
  @objc public let family: FBControlCoreProductFamily

  @objc(genericWithName:)
  public class func generic(withName name: String) -> FBDeviceType {
    return FBDeviceType(model: FBDeviceModel(rawValue: name), productTypes: [], deviceArchitecture: .arm64, family: .familyUnknown)
  }

  private init(model: FBDeviceModel, productTypes: Set<String>, deviceArchitecture: FBArchitecture, family: FBControlCoreProductFamily) {
    self.model = model
    self.productTypes = productTypes
    self.deviceArchitecture = deviceArchitecture
    self.family = family
    super.init()
  }

  // MARK: NSObject

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBDeviceType else { return false }
    return model == other.model
  }

  public override var hash: Int {
    return model.hashValue
  }

  public override var description: String {
    return "Model '\(model.rawValue)'"
  }

  // MARK: NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    return self
  }

  // MARK: Fileprivate Helpers

  fileprivate class func iPhone(withModel model: FBDeviceModel, productType: String, deviceArchitecture: FBArchitecture) -> FBDeviceType {
    return iPhone(withModel: model, productTypes: [productType], deviceArchitecture: deviceArchitecture)
  }

  fileprivate class func iPhone(withModel model: FBDeviceModel, productTypes: [String], deviceArchitecture: FBArchitecture) -> FBDeviceType {
    return FBDeviceType(model: model, productTypes: Set(productTypes), deviceArchitecture: deviceArchitecture, family: .familyiPhone)
  }

  fileprivate class func iPad(withModel model: FBDeviceModel, productTypes: [String], deviceArchitecture: FBArchitecture) -> FBDeviceType {
    return FBDeviceType(model: model, productTypes: Set(productTypes), deviceArchitecture: deviceArchitecture, family: .familyiPad)
  }

  fileprivate class func tv(withModel model: FBDeviceModel, productTypes: [String], deviceArchitecture: FBArchitecture) -> FBDeviceType {
    return FBDeviceType(model: model, productTypes: Set(productTypes), deviceArchitecture: deviceArchitecture, family: .familyAppleTV)
  }

  fileprivate class func watch(withModel model: FBDeviceModel, productTypes: [String], deviceArchitecture: FBArchitecture) -> FBDeviceType {
    return FBDeviceType(model: model, productTypes: Set(productTypes), deviceArchitecture: deviceArchitecture, family: .familyAppleWatch)
  }

  fileprivate class func generic(withModel model: String) -> FBDeviceType {
    return FBDeviceType(model: FBDeviceModel(rawValue: model), productTypes: [], deviceArchitecture: .arm64, family: .familyUnknown)
  }
}

// MARK: - FBOSVersion

@objc(FBOSVersion)
public final class FBOSVersion: NSObject, NSCopying {

  @objc public let name: FBOSVersionName
  @objc public let families: Set<NSNumber>

  @objc(genericWithName:)
  public class func generic(withName name: String) -> FBOSVersion {
    return FBOSVersion(name: FBOSVersionName(rawValue: name), families: [])
  }

  @objc(operatingSystemVersionFromName:)
  public class func operatingSystemVersion(fromName name: String) -> OperatingSystemVersion {
    let components = name.components(separatedBy: CharacterSet.punctuationCharacters)
    var version = OperatingSystemVersion(majorVersion: 0, minorVersion: 0, patchVersion: 0)
    for (index, component) in components.enumerated() {
      let value = Int(component) ?? 0
      switch index {
      case 0:
        version.majorVersion = value
      case 1:
        version.minorVersion = value
      case 2:
        version.patchVersion = value
      default:
        continue
      }
    }
    return version
  }

  private init(name: FBOSVersionName, families: Set<NSNumber>) {
    self.name = name
    self.families = families
    super.init()
  }

  // MARK: Public Computed Properties

  @objc public var versionString: String {
    return (name.rawValue as String).components(separatedBy: CharacterSet.whitespaces)[1]
  }

  @objc public var number: NSDecimalNumber {
    return NSDecimalNumber(string: versionString)
  }

  @objc public var version: OperatingSystemVersion {
    return FBOSVersion.operatingSystemVersion(fromName: versionString)
  }

  // MARK: NSObject

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBOSVersion else { return false }
    return name == other.name
  }

  public override var hash: Int {
    return name.hashValue
  }

  public override var description: String {
    return "OS '\(name.rawValue)'"
  }

  // MARK: NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    return self
  }

  // MARK: Fileprivate Helpers

  fileprivate class func iOS(withName name: FBOSVersionName) -> FBOSVersion {
    let families: Set<NSNumber> = [
      NSNumber(value: FBControlCoreProductFamily.familyiPhone.rawValue),
      NSNumber(value: FBControlCoreProductFamily.familyiPad.rawValue),
    ]
    return FBOSVersion(name: name, families: families)
  }

  fileprivate class func tvOS(withName name: FBOSVersionName) -> FBOSVersion {
    return FBOSVersion(name: name, families: [NSNumber(value: FBControlCoreProductFamily.familyAppleTV.rawValue)])
  }

  fileprivate class func watchOS(withName name: FBOSVersionName) -> FBOSVersion {
    return FBOSVersion(name: name, families: [NSNumber(value: FBControlCoreProductFamily.familyAppleWatch.rawValue)])
  }

  fileprivate class func macOS(withName name: FBOSVersionName) -> FBOSVersion {
    return FBOSVersion(name: name, families: [NSNumber(value: FBControlCoreProductFamily.familyMac.rawValue)])
  }
}

// MARK: - FBiOSTargetConfiguration

@objc(FBiOSTargetConfiguration)
public final class FBiOSTargetConfiguration: NSObject {

  // MARK: Device Configurations

  nonisolated(unsafe) private static let _deviceConfigurations: [FBDeviceType] = {
    return [
      FBDeviceType.iPhone(withModel: .modeliPhone4s, productType: "iPhone4,1", deviceArchitecture: .armv7),
      FBDeviceType.iPhone(withModel: .modeliPhone5, productTypes: ["iPhone5,1", "iPhone5,2"], deviceArchitecture: .armv7s),
      FBDeviceType.iPhone(withModel: .modeliPhone5c, productTypes: ["iPhone5,3"], deviceArchitecture: .armv7s),
      FBDeviceType.iPhone(withModel: .modeliPhone5s, productTypes: ["iPhone6,1", "iPhone6,2"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone6, productType: "iPhone7,2", deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone6Plus, productType: "iPhone7,1", deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone6S, productType: "iPhone8,1", deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone6SPlus, productType: "iPhone8,2", deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhoneSE_1stGeneration, productType: "iPhone8,4", deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhoneSE_2ndGeneration, productType: "iPhone12,8", deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone7, productTypes: ["iPhone9,1", "iPhone9,2", "iPhone9,3"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone7Plus, productTypes: ["iPhone9,2", "iPhone9,4"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone8, productTypes: ["iPhone10,1", "iPhone10,4"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone8Plus, productTypes: ["iPhone10,2", "iPhone10,5"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhoneX, productTypes: ["iPhone10,3", "iPhone10,6"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhoneXs, productTypes: ["iPhone11,2"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhoneXsMax, productTypes: ["iPhone11,6"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhoneXr, productTypes: ["iPhone11,8"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone11, productTypes: ["iPhone12,1"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone11Pro, productTypes: ["iPhone12,3"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone11ProMax, productTypes: ["iPhone12,5"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone12mini, productTypes: ["iPhone13,1"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone12, productTypes: ["iPhone13,2"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone12Pro, productTypes: ["iPhone13,3"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone12ProMax, productTypes: ["iPhone13,4"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone13mini, productTypes: ["iPhone14,4"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone13, productTypes: ["iPhone14,5"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone13Pro, productTypes: ["iPhone14,2"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone13ProMax, productTypes: ["iPhone14,3"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone14, productTypes: ["iPhone14,7"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone14Plus, productTypes: ["iPhone14,8"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone14Pro, productTypes: ["iPhone15,2"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone14ProMax, productTypes: ["iPhone15,3"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone15, productTypes: ["iPhone15,4"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone15Plus, productTypes: ["iPhone15,5"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone15Pro, productTypes: ["iPhone16,1"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone15ProMax, productTypes: ["iPhone16,2"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone16, productTypes: ["iPhone17,3"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone16Plus, productTypes: ["iPhone17,4"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone16Pro, productTypes: ["iPhone17,1"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone16ProMax, productTypes: ["iPhone17,2"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone16e, productTypes: ["iPhone17,5"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone17, productTypes: ["iPhone18,3"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone17Pro, productTypes: ["iPhone18,1"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPhone17ProMax, productTypes: ["iPhone18,2"], deviceArchitecture: .arm64),
      FBDeviceType.iPhone(withModel: .modeliPodTouch_7thGeneration, productTypes: ["iPod9,1"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPad2, productTypes: ["iPad2,1", "iPad2,2", "iPad2,3", "iPad2,4"], deviceArchitecture: .armv7),
      FBDeviceType.iPad(withModel: .modeliPadRetina, productTypes: ["iPad3,1", "iPad3,2", "iPad3,3", "iPad3,4", "iPad3,5", "iPad3,6"], deviceArchitecture: .armv7),
      FBDeviceType.iPad(withModel: .modeliPadAir, productTypes: ["iPad4,1", "iPad4,2", "iPad4,3"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPadAir2, productTypes: ["iPad5,3", "iPad5,4"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPadAir_3rdGeneration, productTypes: ["iPad11,3", "iPad11,4"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPadAir_4thGeneration, productTypes: ["iPad13,1", "iPad13,2"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPadPro, productTypes: ["iPad6,7", "iPad6,8", "iPad6,3", "iPad6,4"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPadPro_9_7_Inch, productTypes: ["iPad6,3", "iPad6,4"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPadPro_12_9_Inch, productTypes: ["iPad6,7", "iPad6,8"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: FBDeviceModel(rawValue: "iPad (5th generation)"), productTypes: ["iPad6,11", "iPad6,12"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPad_6thGeneration, productTypes: ["iPad7,5", "iPad7,6"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPadPro_12_9_Inch_2ndGeneration, productTypes: ["iPad7,1", "iPad7,2"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPadPro_10_5_Inch, productTypes: ["iPad7,3", "iPad7,4"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPad_7thGeneration, productTypes: ["iPad7,11", "iPad7,12"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPad_8thGeneration, productTypes: ["iPad11,6", "iPad11,7"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPad_9thGeneration, productTypes: ["iPad12,1", "iPad12,2"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPad_10thGeneration, productTypes: ["iPad13,18", "iPad13,19"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPadA16, productTypes: ["iPad16,3", "iPad16,4"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPadPro_12_9_Inch_3rdGeneration, productTypes: ["iPad8,5", "iPad8,6", "iPad8,7", "iPad8,8"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPadPro_12_9_Inch_4thGeneration, productTypes: ["iPad8,11", "iPad8,12"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPadPro_11_Inch_1stGeneration, productTypes: ["iPad8,1", "iPad8,2", "iPad8,3", "iPad8,4"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPadPro_12_9nch_1stGeneration, productTypes: ["iPad8,11", "iPad8,12"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: FBDeviceModel(rawValue: "iPad Pro (12.9-inch) (5th generation)"), productTypes: ["iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPadPro_11_Inch_2ndGeneration, productTypes: ["iPad8,9", "iPad8,10"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: FBDeviceModel(rawValue: "iPad Pro (11-inch) (3rd generation)"), productTypes: ["iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPadMini_2, productTypes: ["iPad4,4", "iPad4,5", "iPad4,6"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPadMini_3, productTypes: ["iPad4,7", "iPad4,8", "iPad4,9"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPadMini_4, productTypes: ["iPad5,1", "iPad5,2"], deviceArchitecture: .arm64),
      FBDeviceType.iPad(withModel: .modeliPadMini_5, productTypes: ["iPad11,1", "iPad11,2"], deviceArchitecture: .arm64),
      FBDeviceType.tv(withModel: FBDeviceModel(rawValue: "Apple TV"), productTypes: ["AppleTV5,3"], deviceArchitecture: .arm64),
      FBDeviceType.tv(withModel: FBDeviceModel(rawValue: "Apple TV 4K"), productTypes: ["AppleTV6,2"], deviceArchitecture: .arm64),
      FBDeviceType.tv(withModel: FBDeviceModel(rawValue: "Apple TV 4K (at 1080p)"), productTypes: ["AppleTV6,2"], deviceArchitecture: .arm64),
      FBDeviceType.tv(withModel: FBDeviceModel(rawValue: "Apple TV 4K (2nd generation)"), productTypes: ["AppleTV11,1"], deviceArchitecture: .arm64),
      FBDeviceType.tv(withModel: FBDeviceModel(rawValue: "Apple TV 4K (at 1080p) (2nd generation)"), productTypes: ["AppleTV11,1"], deviceArchitecture: .arm64),
      FBDeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch - 38mm"), productTypes: ["Watch1,1"], deviceArchitecture: .armv7),
      FBDeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch - 42mm"), productTypes: ["Watch1,2"], deviceArchitecture: .armv7),
      FBDeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch SE - 40mm"), productTypes: ["Watch1,1"], deviceArchitecture: .armv7),
      FBDeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch SE - 44mm"), productTypes: ["Watch1,2"], deviceArchitecture: .armv7),
      FBDeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch Series 2 - 38mm"), productTypes: ["Watch2,1"], deviceArchitecture: .armv7),
      FBDeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch Series 2 - 42mm"), productTypes: ["Watch2,2"], deviceArchitecture: .armv7),
      FBDeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch Series 3 - 38mm"), productTypes: ["Watch3,1"], deviceArchitecture: .armv7),
      FBDeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch Series 3 - 42mm"), productTypes: ["Watch3,2"], deviceArchitecture: .armv7),
      FBDeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch Series 4 - 40mm"), productTypes: ["Watch4,1", "Watch4,3"], deviceArchitecture: .arm64),
      FBDeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch Series 4 - 44mm"), productTypes: ["Watch4,2", "Watch4,4"], deviceArchitecture: .arm64),
      FBDeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch Series 5 - 40mm"), productTypes: ["Watch5,1", "Watch5,3"], deviceArchitecture: .arm64),
      FBDeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch Series 5 - 44mm"), productTypes: ["Watch5,2", "Watch5,4"], deviceArchitecture: .arm64),
      FBDeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch Series 6 - 40mm"), productTypes: ["Watch6,1", "Watch6,3"], deviceArchitecture: .arm64),
      FBDeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch Series 6 - 44mm"), productTypes: ["Watch6,2", "Watch6,4"], deviceArchitecture: .arm64),
    ]
  }()

  // MARK: OS Configurations

  nonisolated(unsafe) private static let _osConfigurations: [FBOSVersion] = {
    return [
      FBOSVersion.iOS(withName: .nameiOS_7_1),
      FBOSVersion.iOS(withName: .nameiOS_8_0),
      FBOSVersion.iOS(withName: .nameiOS_8_1),
      FBOSVersion.iOS(withName: .nameiOS_8_2),
      FBOSVersion.iOS(withName: .nameiOS_8_3),
      FBOSVersion.iOS(withName: .nameiOS_8_4),
      FBOSVersion.iOS(withName: .nameiOS_9_0),
      FBOSVersion.iOS(withName: .nameiOS_9_1),
      FBOSVersion.iOS(withName: .nameiOS_9_2),
      FBOSVersion.iOS(withName: .nameiOS_9_3),
      FBOSVersion.iOS(withName: .nameiOS_9_3_1),
      FBOSVersion.iOS(withName: .nameiOS_9_3_2),
      FBOSVersion.iOS(withName: .nameiOS_10_0),
      FBOSVersion.iOS(withName: .nameiOS_10_1),
      FBOSVersion.iOS(withName: .nameiOS_10_2),
      FBOSVersion.iOS(withName: FBOSVersionName(rawValue: "iOS 10.2.1")),
      FBOSVersion.iOS(withName: .nameiOS_10_3),
      FBOSVersion.iOS(withName: FBOSVersionName(rawValue: "iOS 10.3.1")),
      FBOSVersion.iOS(withName: .nameiOS_11_0),
      FBOSVersion.iOS(withName: .nameiOS_11_1),
      FBOSVersion.iOS(withName: .nameiOS_11_2),
      FBOSVersion.iOS(withName: .nameiOS_11_3),
      FBOSVersion.iOS(withName: .nameiOS_11_4),
      FBOSVersion.iOS(withName: .nameiOS_11_4),
      FBOSVersion.iOS(withName: .nameiOS_12_0),
      FBOSVersion.iOS(withName: .nameiOS_12_1),
      FBOSVersion.iOS(withName: .nameiOS_12_2),
      FBOSVersion.iOS(withName: .nameiOS_12_4),
      FBOSVersion.iOS(withName: .nameiOS_13_0),
      FBOSVersion.iOS(withName: .nameiOS_13_1),
      FBOSVersion.iOS(withName: .nameiOS_13_2),
      FBOSVersion.iOS(withName: .nameiOS_13_3),
      FBOSVersion.iOS(withName: .nameiOS_13_4),
      FBOSVersion.iOS(withName: .nameiOS_13_5),
      FBOSVersion.iOS(withName: FBOSVersionName(rawValue: "iOS 13.6")),
      FBOSVersion.iOS(withName: FBOSVersionName(rawValue: "iOS 13.7")),
      FBOSVersion.iOS(withName: .nameiOS_14_0),
      FBOSVersion.iOS(withName: .nameiOS_14_1),
      FBOSVersion.iOS(withName: .nameiOS_14_2),
      FBOSVersion.iOS(withName: FBOSVersionName(rawValue: "iOS 14.3")),
      FBOSVersion.iOS(withName: FBOSVersionName(rawValue: "iOS 14.4")),
      FBOSVersion.iOS(withName: FBOSVersionName(rawValue: "iOS 14.5")),
      FBOSVersion.tvOS(withName: .nametvOS_9_0),
      FBOSVersion.tvOS(withName: .nametvOS_9_1),
      FBOSVersion.tvOS(withName: .nametvOS_9_2),
      FBOSVersion.tvOS(withName: .nametvOS_10_0),
      FBOSVersion.tvOS(withName: .nametvOS_10_1),
      FBOSVersion.tvOS(withName: .nametvOS_10_2),
      FBOSVersion.tvOS(withName: .nametvOS_11_0),
      FBOSVersion.tvOS(withName: .nametvOS_11_1),
      FBOSVersion.tvOS(withName: .nametvOS_11_2),
      FBOSVersion.tvOS(withName: .nametvOS_11_3),
      FBOSVersion.tvOS(withName: .nametvOS_11_4),
      FBOSVersion.tvOS(withName: .nametvOS_12_0),
      FBOSVersion.tvOS(withName: .nametvOS_12_1),
      FBOSVersion.tvOS(withName: .nametvOS_12_2),
      FBOSVersion.tvOS(withName: .nametvOS_12_4),
      FBOSVersion.tvOS(withName: .nametvOS_13_0),
      FBOSVersion.tvOS(withName: .nametvOS_13_2),
      FBOSVersion.tvOS(withName: .nametvOS_13_3),
      FBOSVersion.tvOS(withName: .nametvOS_13_4),
      FBOSVersion.tvOS(withName: .nametvOS_14_0),
      FBOSVersion.tvOS(withName: .nametvOS_14_1),
      FBOSVersion.tvOS(withName: .nametvOS_14_2),
      FBOSVersion.tvOS(withName: .nametvOS_14_3),
      FBOSVersion.tvOS(withName: FBOSVersionName(rawValue: "tvOS 14.5")),
      FBOSVersion.tvOS(withName: .namewatchOS_2_0),
      FBOSVersion.tvOS(withName: .namewatchOS_2_1),
      FBOSVersion.tvOS(withName: .namewatchOS_2_2),
      FBOSVersion.tvOS(withName: .namewatchOS_3_0),
      FBOSVersion.tvOS(withName: .namewatchOS_3_1),
      FBOSVersion.tvOS(withName: .namewatchOS_3_2),
      FBOSVersion.tvOS(withName: .namewatchOS_4_0),
      FBOSVersion.tvOS(withName: .namewatchOS_4_1),
      FBOSVersion.tvOS(withName: .namewatchOS_4_2),
      FBOSVersion.tvOS(withName: .namewatchOS_5_0),
      FBOSVersion.tvOS(withName: .namewatchOS_5_1),
      FBOSVersion.tvOS(withName: .namewatchOS_5_2),
      FBOSVersion.tvOS(withName: .namewatchOS_5_3),
      FBOSVersion.tvOS(withName: .namewatchOS_6_0),
      FBOSVersion.tvOS(withName: .namewatchOS_6_1),
      FBOSVersion.tvOS(withName: .namewatchOS_6_2),
      FBOSVersion.tvOS(withName: .namewatchOS_7_0),
      FBOSVersion.tvOS(withName: .namewatchOS_7_1),
      FBOSVersion.tvOS(withName: .namewatchOS_7_2),
      FBOSVersion.tvOS(withName: .namewatchOS_7_4),
      FBOSVersion.macOS(withName: .namemac),
    ]
  }()

  // MARK: Class Properties

  nonisolated(unsafe) private static let _nameToDevice: [FBDeviceModel: FBDeviceType] = {
    var dictionary = [FBDeviceModel: FBDeviceType]()
    for device in _deviceConfigurations {
      dictionary[device.model] = device
    }
    return dictionary
  }()

  nonisolated(unsafe) private static let _productTypeToDevice: [String: FBDeviceType] = {
    var dictionary = [String: FBDeviceType]()
    for device in _deviceConfigurations {
      for productType in device.productTypes {
        dictionary[productType] = device
      }
    }
    return dictionary
  }()

  nonisolated(unsafe) private static let _nameToOSVersion: [FBOSVersionName: FBOSVersion] = {
    var dictionary = [FBOSVersionName: FBOSVersion]()
    for os in _osConfigurations {
      dictionary[os.name] = os
    }
    return dictionary
  }()

  @objc public class var nameToDevice: [FBDeviceModel: FBDeviceType] {
    return _nameToDevice
  }

  @objc public class var productTypeToDevice: [String: FBDeviceType] {
    return _productTypeToDevice
  }

  @objc public class var nameToOSVersion: [FBOSVersionName: FBOSVersion] {
    return _nameToOSVersion
  }

  // MARK: Public Methods

  @objc(baseArchsToCompatibleArch:)
  public class func baseArchsToCompatibleArch(_ architectures: [FBArchitecture]) -> Set<FBArchitecture> {
    let mapping: [FBArchitecture: Set<FBArchitecture>] = [
      .arm64e: [.arm64e, .arm64, .armv7s, .armv7],
      .arm64: [.arm64, .armv7s, .armv7],
      .armv7s: [.armv7s, .armv7],
      .armv7: [.armv7],
      FBArchitecture(rawValue: "i386"): [FBArchitecture(rawValue: "i386")],
      FBArchitecture(rawValue: "x86_64"): [FBArchitecture(rawValue: "x86_64"), FBArchitecture(rawValue: "i386")],
    ]

    var result = Set<FBArchitecture>()
    for arch in architectures {
      if let compatible = mapping[arch] {
        result.formUnion(compatible)
      }
    }
    return result
  }
}
