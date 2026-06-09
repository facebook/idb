/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBXcodeConfiguration)
public class FBXcodeConfiguration: NSObject {

  // MARK: Public Properties

  @objc public static let developerDirectory: String = {
    (try? FBXcodeDirectory.resolveDeveloperDirectory()) ?? ""
  }()

  @objc public static let contentsDirectory: String = {
    (developerDirectory as NSString).deletingLastPathComponent
  }()

  @objc public static let xcodeVersionNumber: NSDecimalNumber = {
    let versionString = FBXcodeConfiguration.readValue(forKey: "CFBundleShortVersionString", fromPlistAtPath: FBXcodeConfiguration.xcodeInfoPlistPath)
    return NSDecimalNumber(string: versionString as? String)
  }()

  @objc public static let xcodeVersion: OperatingSystemVersion = {
    return FBOSVersion.operatingSystemVersion(fromName: xcodeVersionNumber.stringValue)
  }()

  @objc public static let iosSDKVersionNumber: NSDecimalNumber = {
    NSDecimalNumber(string: iosSDKVersion)
  }()

  @objc public static let iosSDKVersionNumberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 1
    formatter.maximumFractionDigits = 3
    return formatter
  }()

  @objc public static let iosSDKVersion: String = {
    return FBXcodeConfiguration.readValue(forKey: "Version", fromPlistAtPath: FBXcodeConfiguration.iPhoneSimulatorPlatformInfoPlistPath) as? String ?? ""
  }()

  @objc public static let isXcode12OrGreater: Bool = {
    xcodeVersionNumber.compare(NSDecimalNumber(string: "12.0")) != .orderedAscending
  }()

  @objc public static let isXcode12_5OrGreater: Bool = {
    xcodeVersionNumber.compare(NSDecimalNumber(string: "12.5")) != .orderedAscending
  }()

  @objc public static let simulatorApp: FBBundleDescriptor = {
    let path = simulatorApplicationPath
    guard let bundle = Bundle(path: path) else {
      fatalError("Could not load Simulator.app bundle at '\(path)'")
    }
    let name =
      (bundle.infoDictionary?["CFBundleName"] as? String)
      ?? (bundle.infoDictionary?["CFBundleExecutable"] as? String)
      ?? ((path as NSString).deletingPathExtension as NSString).lastPathComponent
    let identifier = bundle.bundleIdentifier ?? "com.apple.iphonesimulator"
    // We deliberately don't include the binary because we should never need it.
    return FBBundleDescriptor(name: name, identifier: identifier, path: path, binary: nil)
  }()

  // MARK: NSObject

  override public class func description() -> String {
    "Developer Directory \(developerDirectory) | Xcode Version \(xcodeVersionNumber) | iOS SDK Version \(iosSDKVersionNumber)"
  }

  public override var description: String {
    Self.description()
  }

  // MARK: Private

  fileprivate class var simulatorApplicationPath: String {
    // Xcode 27 renamed Simulator.app to DeviceHub.app and moved it from
    // Contents/Developer/Applications to Contents/Applications. Prefer the new
    // location, falling back to the legacy Simulator.app for Xcode <= 26.
    let deviceHubPath = ((contentsDirectory as NSString).appendingPathComponent("Applications") as NSString).appendingPathComponent("DeviceHub.app")
    if FileManager.default.fileExists(atPath: deviceHubPath) {
      return deviceHubPath
    }
    return ((developerDirectory as NSString).appendingPathComponent("Applications") as NSString).appendingPathComponent("Simulator.app")
  }

  fileprivate class var iPhoneSimulatorPlatformInfoPlistPath: String {
    ((developerDirectory as NSString).appendingPathComponent("Platforms/iPhoneSimulator.platform") as NSString).appendingPathComponent("Info.plist")
  }

  fileprivate class var xcodeInfoPlistPath: String {
    ((developerDirectory as NSString).deletingLastPathComponent as NSString).appendingPathComponent("Info.plist")
  }

  fileprivate class func readValue(forKey key: String, fromPlistAtPath plistPath: String) -> Any? {
    assert(FileManager.default.fileExists(atPath: plistPath), "plist does not exist at path '\(plistPath)'")
    guard let infoPlist = NSDictionary(contentsOfFile: plistPath) else {
      assertionFailure("Could not read plist at '\(plistPath)'")
      return nil
    }
    let value = infoPlist[key]
    assert(value != nil, "'\(key)' does not exist in plist '\(infoPlist.allKeys)'")
    return value
  }

}
