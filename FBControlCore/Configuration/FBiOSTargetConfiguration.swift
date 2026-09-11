/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// MARK: - FBiOSTargetScreenInfo

public struct FBiOSTargetScreenInfo: Equatable, Hashable, CustomStringConvertible {

  public let widthPixels: UInt
  public let heightPixels: UInt
  public let scale: Float

  public init(widthPixels: UInt, heightPixels: UInt, scale: Float) {
    self.widthPixels = widthPixels
    self.heightPixels = heightPixels
    self.scale = scale
  }

  /// Truncating the scale to `Int` means two screens differing only in the fraction of their scale
  /// collide, which equality still separates.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(Int(widthPixels) ^ Int(heightPixels) ^ Int(scale))
  }

  public var description: String {
    String(format: "Screen Pixels %lu,%lu | Scale %fX", widthPixels, heightPixels, scale)
  }
}

// MARK: - DeviceType

public struct DeviceType: Equatable, Hashable, CustomStringConvertible, Sendable {

  public let model: FBDeviceModel
  public let productTypes: Set<String>
  public let deviceArchitecture: FBArchitecture
  public let family: FBControlCoreProductFamily

  public static func generic(withName name: String) -> DeviceType {
    DeviceType(model: FBDeviceModel(rawValue: name), productTypes: [], deviceArchitecture: .arm64, family: .familyUnknown)
  }

  private init(model: FBDeviceModel, productTypes: Set<String>, deviceArchitecture: FBArchitecture, family: FBControlCoreProductFamily) {
    self.model = model
    self.productTypes = productTypes
    self.deviceArchitecture = deviceArchitecture
    self.family = family
  }

  /// The model is the identity: the other properties are catalogue data looked up from it, so a
  /// catalogue entry and a generic device type of the same model are equal.
  public static func == (lhs: DeviceType, rhs: DeviceType) -> Bool {
    lhs.model == rhs.model
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(model)
  }

  public var description: String {
    "Model '\(model.rawValue)'"
  }

  // MARK: - Fileprivate Helpers

  fileprivate static func iPhone(withModel model: FBDeviceModel, productType: String, deviceArchitecture: FBArchitecture) -> DeviceType {
    iPhone(withModel: model, productTypes: [productType], deviceArchitecture: deviceArchitecture)
  }

  fileprivate static func iPhone(withModel model: FBDeviceModel, productTypes: [String], deviceArchitecture: FBArchitecture) -> DeviceType {
    DeviceType(model: model, productTypes: Set(productTypes), deviceArchitecture: deviceArchitecture, family: .familyiPhone)
  }

  fileprivate static func iPad(withModel model: FBDeviceModel, productTypes: [String], deviceArchitecture: FBArchitecture) -> DeviceType {
    DeviceType(model: model, productTypes: Set(productTypes), deviceArchitecture: deviceArchitecture, family: .familyiPad)
  }

  fileprivate static func tv(withModel model: FBDeviceModel, productTypes: [String], deviceArchitecture: FBArchitecture) -> DeviceType {
    DeviceType(model: model, productTypes: Set(productTypes), deviceArchitecture: deviceArchitecture, family: .familyAppleTV)
  }

  fileprivate static func watch(withModel model: FBDeviceModel, productTypes: [String], deviceArchitecture: FBArchitecture) -> DeviceType {
    DeviceType(model: model, productTypes: Set(productTypes), deviceArchitecture: deviceArchitecture, family: .familyAppleWatch)
  }

  fileprivate static func generic(withModel model: String) -> DeviceType {
    DeviceType(model: FBDeviceModel(rawValue: model), productTypes: [], deviceArchitecture: .arm64, family: .familyUnknown)
  }
}

// MARK: - OSVersion

public struct OSVersion: Equatable, Hashable, CustomStringConvertible, Sendable {

  public let name: FBOSVersionName
  public let families: Set<NSNumber>

  public static func generic(withName name: String) -> OSVersion {
    OSVersion(name: FBOSVersionName(rawValue: name), families: [])
  }

  public static func operatingSystemVersion(fromName name: String) -> OperatingSystemVersion {
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
  }

  // MARK: - Public Computed Properties

  public var versionString: String {
    (name.rawValue as String).components(separatedBy: CharacterSet.whitespaces)[1]
  }

  public var number: NSDecimalNumber {
    NSDecimalNumber(string: versionString)
  }

  public var version: OperatingSystemVersion {
    OSVersion.operatingSystemVersion(fromName: versionString)
  }

  /// The name is the identity: `families` is catalogue data looked up from it.
  public static func == (lhs: OSVersion, rhs: OSVersion) -> Bool {
    lhs.name == rhs.name
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(name)
  }

  public var description: String {
    "OS '\(name.rawValue)'"
  }

  // MARK: - Fileprivate Helpers

  fileprivate static func iOS(withName name: FBOSVersionName) -> OSVersion {
    let families: Set<NSNumber> = [
      NSNumber(value: FBControlCoreProductFamily.familyiPhone.rawValue),
      NSNumber(value: FBControlCoreProductFamily.familyiPad.rawValue),
    ]
    return OSVersion(name: name, families: families)
  }

  fileprivate static func tvOS(withName name: FBOSVersionName) -> OSVersion {
    OSVersion(name: name, families: [NSNumber(value: FBControlCoreProductFamily.familyAppleTV.rawValue)])
  }

  fileprivate static func watchOS(withName name: FBOSVersionName) -> OSVersion {
    OSVersion(name: name, families: [NSNumber(value: FBControlCoreProductFamily.familyAppleWatch.rawValue)])
  }

  fileprivate static func macOS(withName name: FBOSVersionName) -> OSVersion {
    OSVersion(name: name, families: [NSNumber(value: FBControlCoreProductFamily.familyMac.rawValue)])
  }
}

@objc
public final class FBiOSTargetConfiguration: NSObject {

  private static let _deviceConfigurations: [DeviceType] = {
    [
      DeviceType.iPhone(withModel: .modeliPhone4s, productType: "iPhone4,1", deviceArchitecture: .armv7),
      DeviceType.iPhone(withModel: .modeliPhone5, productTypes: ["iPhone5,1", "iPhone5,2"], deviceArchitecture: .armv7s),
      DeviceType.iPhone(withModel: .modeliPhone5c, productTypes: ["iPhone5,3"], deviceArchitecture: .armv7s),
      DeviceType.iPhone(withModel: .modeliPhone5s, productTypes: ["iPhone6,1", "iPhone6,2"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone6, productType: "iPhone7,2", deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone6Plus, productType: "iPhone7,1", deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone6S, productType: "iPhone8,1", deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone6SPlus, productType: "iPhone8,2", deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhoneSE_1stGeneration, productType: "iPhone8,4", deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhoneSE_2ndGeneration, productType: "iPhone12,8", deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone7, productTypes: ["iPhone9,1", "iPhone9,2", "iPhone9,3"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone7Plus, productTypes: ["iPhone9,2", "iPhone9,4"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone8, productTypes: ["iPhone10,1", "iPhone10,4"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone8Plus, productTypes: ["iPhone10,2", "iPhone10,5"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhoneX, productTypes: ["iPhone10,3", "iPhone10,6"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhoneXs, productTypes: ["iPhone11,2"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhoneXsMax, productTypes: ["iPhone11,6"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhoneXr, productTypes: ["iPhone11,8"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone11, productTypes: ["iPhone12,1"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone11Pro, productTypes: ["iPhone12,3"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone11ProMax, productTypes: ["iPhone12,5"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone12mini, productTypes: ["iPhone13,1"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone12, productTypes: ["iPhone13,2"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone12Pro, productTypes: ["iPhone13,3"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone12ProMax, productTypes: ["iPhone13,4"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone13mini, productTypes: ["iPhone14,4"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone13, productTypes: ["iPhone14,5"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone13Pro, productTypes: ["iPhone14,2"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone13ProMax, productTypes: ["iPhone14,3"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone14, productTypes: ["iPhone14,7"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone14Plus, productTypes: ["iPhone14,8"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone14Pro, productTypes: ["iPhone15,2"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone14ProMax, productTypes: ["iPhone15,3"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone15, productTypes: ["iPhone15,4"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone15Plus, productTypes: ["iPhone15,5"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone15Pro, productTypes: ["iPhone16,1"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone15ProMax, productTypes: ["iPhone16,2"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone16, productTypes: ["iPhone17,3"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone16Plus, productTypes: ["iPhone17,4"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone16Pro, productTypes: ["iPhone17,1"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone16ProMax, productTypes: ["iPhone17,2"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone16e, productTypes: ["iPhone17,5"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone17, productTypes: ["iPhone18,3"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone17Pro, productTypes: ["iPhone18,1"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPhone17ProMax, productTypes: ["iPhone18,2"], deviceArchitecture: .arm64),
      DeviceType.iPhone(withModel: .modeliPodTouch_7thGeneration, productTypes: ["iPod9,1"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPad2, productTypes: ["iPad2,1", "iPad2,2", "iPad2,3", "iPad2,4"], deviceArchitecture: .armv7),
      DeviceType.iPad(withModel: .modeliPadRetina, productTypes: ["iPad3,1", "iPad3,2", "iPad3,3", "iPad3,4", "iPad3,5", "iPad3,6"], deviceArchitecture: .armv7),
      DeviceType.iPad(withModel: .modeliPadAir, productTypes: ["iPad4,1", "iPad4,2", "iPad4,3"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPadAir2, productTypes: ["iPad5,3", "iPad5,4"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPadAir_3rdGeneration, productTypes: ["iPad11,3", "iPad11,4"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPadAir_4thGeneration, productTypes: ["iPad13,1", "iPad13,2"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPadPro, productTypes: ["iPad6,7", "iPad6,8", "iPad6,3", "iPad6,4"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPadPro_9_7_Inch, productTypes: ["iPad6,3", "iPad6,4"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPadPro_12_9_Inch, productTypes: ["iPad6,7", "iPad6,8"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: FBDeviceModel(rawValue: "iPad (5th generation)"), productTypes: ["iPad6,11", "iPad6,12"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPad_6thGeneration, productTypes: ["iPad7,5", "iPad7,6"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPadPro_12_9_Inch_2ndGeneration, productTypes: ["iPad7,1", "iPad7,2"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPadPro_10_5_Inch, productTypes: ["iPad7,3", "iPad7,4"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPad_7thGeneration, productTypes: ["iPad7,11", "iPad7,12"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPad_8thGeneration, productTypes: ["iPad11,6", "iPad11,7"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPad_9thGeneration, productTypes: ["iPad12,1", "iPad12,2"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPad_10thGeneration, productTypes: ["iPad13,18", "iPad13,19"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPadA16, productTypes: ["iPad16,3", "iPad16,4"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPadPro_12_9_Inch_3rdGeneration, productTypes: ["iPad8,5", "iPad8,6", "iPad8,7", "iPad8,8"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPadPro_12_9_Inch_4thGeneration, productTypes: ["iPad8,11", "iPad8,12"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPadPro_11_Inch_1stGeneration, productTypes: ["iPad8,1", "iPad8,2", "iPad8,3", "iPad8,4"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPadPro_12_9nch_1stGeneration, productTypes: ["iPad8,11", "iPad8,12"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: FBDeviceModel(rawValue: "iPad Pro (12.9-inch) (5th generation)"), productTypes: ["iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPadPro_11_Inch_2ndGeneration, productTypes: ["iPad8,9", "iPad8,10"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: FBDeviceModel(rawValue: "iPad Pro (11-inch) (3rd generation)"), productTypes: ["iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPadMini_2, productTypes: ["iPad4,4", "iPad4,5", "iPad4,6"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPadMini_3, productTypes: ["iPad4,7", "iPad4,8", "iPad4,9"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPadMini_4, productTypes: ["iPad5,1", "iPad5,2"], deviceArchitecture: .arm64),
      DeviceType.iPad(withModel: .modeliPadMini_5, productTypes: ["iPad11,1", "iPad11,2"], deviceArchitecture: .arm64),
      DeviceType.tv(withModel: FBDeviceModel(rawValue: "Apple TV"), productTypes: ["AppleTV5,3"], deviceArchitecture: .arm64),
      DeviceType.tv(withModel: FBDeviceModel(rawValue: "Apple TV 4K"), productTypes: ["AppleTV6,2"], deviceArchitecture: .arm64),
      DeviceType.tv(withModel: FBDeviceModel(rawValue: "Apple TV 4K (at 1080p)"), productTypes: ["AppleTV6,2"], deviceArchitecture: .arm64),
      DeviceType.tv(withModel: FBDeviceModel(rawValue: "Apple TV 4K (2nd generation)"), productTypes: ["AppleTV11,1"], deviceArchitecture: .arm64),
      DeviceType.tv(withModel: FBDeviceModel(rawValue: "Apple TV 4K (at 1080p) (2nd generation)"), productTypes: ["AppleTV11,1"], deviceArchitecture: .arm64),
      DeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch - 38mm"), productTypes: ["Watch1,1"], deviceArchitecture: .armv7),
      DeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch - 42mm"), productTypes: ["Watch1,2"], deviceArchitecture: .armv7),
      DeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch SE - 40mm"), productTypes: ["Watch1,1"], deviceArchitecture: .armv7),
      DeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch SE - 44mm"), productTypes: ["Watch1,2"], deviceArchitecture: .armv7),
      DeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch Series 2 - 38mm"), productTypes: ["Watch2,1"], deviceArchitecture: .armv7),
      DeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch Series 2 - 42mm"), productTypes: ["Watch2,2"], deviceArchitecture: .armv7),
      DeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch Series 3 - 38mm"), productTypes: ["Watch3,1"], deviceArchitecture: .armv7),
      DeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch Series 3 - 42mm"), productTypes: ["Watch3,2"], deviceArchitecture: .armv7),
      DeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch Series 4 - 40mm"), productTypes: ["Watch4,1", "Watch4,3"], deviceArchitecture: .arm64),
      DeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch Series 4 - 44mm"), productTypes: ["Watch4,2", "Watch4,4"], deviceArchitecture: .arm64),
      DeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch Series 5 - 40mm"), productTypes: ["Watch5,1", "Watch5,3"], deviceArchitecture: .arm64),
      DeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch Series 5 - 44mm"), productTypes: ["Watch5,2", "Watch5,4"], deviceArchitecture: .arm64),
      DeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch Series 6 - 40mm"), productTypes: ["Watch6,1", "Watch6,3"], deviceArchitecture: .arm64),
      DeviceType.watch(withModel: FBDeviceModel(rawValue: "Apple Watch Series 6 - 44mm"), productTypes: ["Watch6,2", "Watch6,4"], deviceArchitecture: .arm64),
    ]
  }()

  private static let _osConfigurations: [OSVersion] = {
    [
      OSVersion.iOS(withName: .nameiOS_7_1),
      OSVersion.iOS(withName: .nameiOS_8_0),
      OSVersion.iOS(withName: .nameiOS_8_1),
      OSVersion.iOS(withName: .nameiOS_8_2),
      OSVersion.iOS(withName: .nameiOS_8_3),
      OSVersion.iOS(withName: .nameiOS_8_4),
      OSVersion.iOS(withName: .nameiOS_9_0),
      OSVersion.iOS(withName: .nameiOS_9_1),
      OSVersion.iOS(withName: .nameiOS_9_2),
      OSVersion.iOS(withName: .nameiOS_9_3),
      OSVersion.iOS(withName: .nameiOS_9_3_1),
      OSVersion.iOS(withName: .nameiOS_9_3_2),
      OSVersion.iOS(withName: .nameiOS_10_0),
      OSVersion.iOS(withName: .nameiOS_10_1),
      OSVersion.iOS(withName: .nameiOS_10_2),
      OSVersion.iOS(withName: FBOSVersionName(rawValue: "iOS 10.2.1")),
      OSVersion.iOS(withName: .nameiOS_10_3),
      OSVersion.iOS(withName: FBOSVersionName(rawValue: "iOS 10.3.1")),
      OSVersion.iOS(withName: .nameiOS_11_0),
      OSVersion.iOS(withName: .nameiOS_11_1),
      OSVersion.iOS(withName: .nameiOS_11_2),
      OSVersion.iOS(withName: .nameiOS_11_3),
      OSVersion.iOS(withName: .nameiOS_11_4),
      OSVersion.iOS(withName: .nameiOS_11_4),
      OSVersion.iOS(withName: .nameiOS_12_0),
      OSVersion.iOS(withName: .nameiOS_12_1),
      OSVersion.iOS(withName: .nameiOS_12_2),
      OSVersion.iOS(withName: .nameiOS_12_4),
      OSVersion.iOS(withName: .nameiOS_13_0),
      OSVersion.iOS(withName: .nameiOS_13_1),
      OSVersion.iOS(withName: .nameiOS_13_2),
      OSVersion.iOS(withName: .nameiOS_13_3),
      OSVersion.iOS(withName: .nameiOS_13_4),
      OSVersion.iOS(withName: .nameiOS_13_5),
      OSVersion.iOS(withName: FBOSVersionName(rawValue: "iOS 13.6")),
      OSVersion.iOS(withName: FBOSVersionName(rawValue: "iOS 13.7")),
      OSVersion.iOS(withName: .nameiOS_14_0),
      OSVersion.iOS(withName: .nameiOS_14_1),
      OSVersion.iOS(withName: .nameiOS_14_2),
      OSVersion.iOS(withName: FBOSVersionName(rawValue: "iOS 14.3")),
      OSVersion.iOS(withName: FBOSVersionName(rawValue: "iOS 14.4")),
      OSVersion.iOS(withName: FBOSVersionName(rawValue: "iOS 14.5")),
      OSVersion.tvOS(withName: .nametvOS_9_0),
      OSVersion.tvOS(withName: .nametvOS_9_1),
      OSVersion.tvOS(withName: .nametvOS_9_2),
      OSVersion.tvOS(withName: .nametvOS_10_0),
      OSVersion.tvOS(withName: .nametvOS_10_1),
      OSVersion.tvOS(withName: .nametvOS_10_2),
      OSVersion.tvOS(withName: .nametvOS_11_0),
      OSVersion.tvOS(withName: .nametvOS_11_1),
      OSVersion.tvOS(withName: .nametvOS_11_2),
      OSVersion.tvOS(withName: .nametvOS_11_3),
      OSVersion.tvOS(withName: .nametvOS_11_4),
      OSVersion.tvOS(withName: .nametvOS_12_0),
      OSVersion.tvOS(withName: .nametvOS_12_1),
      OSVersion.tvOS(withName: .nametvOS_12_2),
      OSVersion.tvOS(withName: .nametvOS_12_4),
      OSVersion.tvOS(withName: .nametvOS_13_0),
      OSVersion.tvOS(withName: .nametvOS_13_2),
      OSVersion.tvOS(withName: .nametvOS_13_3),
      OSVersion.tvOS(withName: .nametvOS_13_4),
      OSVersion.tvOS(withName: .nametvOS_14_0),
      OSVersion.tvOS(withName: .nametvOS_14_1),
      OSVersion.tvOS(withName: .nametvOS_14_2),
      OSVersion.tvOS(withName: .nametvOS_14_3),
      OSVersion.tvOS(withName: FBOSVersionName(rawValue: "tvOS 14.5")),
      OSVersion.watchOS(withName: .namewatchOS_2_0),
      OSVersion.watchOS(withName: .namewatchOS_2_1),
      OSVersion.watchOS(withName: .namewatchOS_2_2),
      OSVersion.watchOS(withName: .namewatchOS_3_0),
      OSVersion.watchOS(withName: .namewatchOS_3_1),
      OSVersion.watchOS(withName: .namewatchOS_3_2),
      OSVersion.watchOS(withName: .namewatchOS_4_0),
      OSVersion.watchOS(withName: .namewatchOS_4_1),
      OSVersion.watchOS(withName: .namewatchOS_4_2),
      OSVersion.watchOS(withName: .namewatchOS_5_0),
      OSVersion.watchOS(withName: .namewatchOS_5_1),
      OSVersion.watchOS(withName: .namewatchOS_5_2),
      OSVersion.watchOS(withName: .namewatchOS_5_3),
      OSVersion.watchOS(withName: .namewatchOS_6_0),
      OSVersion.watchOS(withName: .namewatchOS_6_1),
      OSVersion.watchOS(withName: .namewatchOS_6_2),
      OSVersion.watchOS(withName: .namewatchOS_7_0),
      OSVersion.watchOS(withName: .namewatchOS_7_1),
      OSVersion.watchOS(withName: .namewatchOS_7_2),
      OSVersion.watchOS(withName: .namewatchOS_7_3),
      OSVersion.watchOS(withName: .namewatchOS_7_4),
      OSVersion.macOS(withName: .namemac),
    ]
  }()

  // MARK: - Class Properties

  public static let nameToDevice: [FBDeviceModel: DeviceType] = {
    var dictionary = [FBDeviceModel: DeviceType]()
    for device in _deviceConfigurations {
      dictionary[device.model] = device
    }
    return dictionary
  }()

  public static let productTypeToDevice: [String: DeviceType] = {
    var dictionary = [String: DeviceType]()
    for device in _deviceConfigurations {
      for productType in device.productTypes {
        dictionary[productType] = device
      }
    }
    return dictionary
  }()

  public static let nameToOSVersion: [FBOSVersionName: OSVersion] = {
    var dictionary = [FBOSVersionName: OSVersion]()
    for os in _osConfigurations {
      dictionary[os.name] = os
    }
    return dictionary
  }()

  // MARK: - Public Methods

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
