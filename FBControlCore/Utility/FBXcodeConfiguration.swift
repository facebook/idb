/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// Lazy thread-safe initialization (equivalent to dispatch_once)
private let _xcodeVersionNumber: NSDecimalNumber = {
  let versionString = FBXcodeConfiguration.readValue(forKey: "CFBundleShortVersionString", fromPlistAtPath: FBXcodeConfiguration.xcodeInfoPlistPath)
  return NSDecimalNumber(string: versionString as? String)
}()

private let _xcodeVersion: OperatingSystemVersion = {
  return FBOSVersion.operatingSystemVersion(fromName: _xcodeVersionNumber.stringValue)
}()

private let _iosSDKVersion: String = {
  return FBXcodeConfiguration.readValue(forKey: "Version", fromPlistAtPath: FBXcodeConfiguration.iPhoneSimulatorPlatformInfoPlistPath) as! String
}()

private let _iosSDKVersionNumberFormatter: NumberFormatter = {
  let formatter = NumberFormatter()
  formatter.numberStyle = .decimal
  formatter.minimumFractionDigits = 1
  formatter.maximumFractionDigits = 3
  return formatter
}()

private let _developerDirectoryResult: (directory: String?, error: NSError?) = {
  do {
    let dir = try FBXcodeDirectory.symlinkedDeveloperDirectory()
    return (dir, nil)
  } catch {
    return (nil, error as NSError)
  }
}()

@objc(FBXcodeConfiguration)
public class FBXcodeConfiguration: NSObject {

  // MARK: Public Properties

  @objc public class var developerDirectory: String {
    return findXcodeDeveloperDirectoryOrAssert()
  }

  @objc public class var contentsDirectory: String {
    return (developerDirectory as NSString).deletingLastPathComponent
  }

  @objc public class var xcodeVersionNumber: NSDecimalNumber {
    return _xcodeVersionNumber
  }

  @objc public class var xcodeVersion: OperatingSystemVersion {
    return _xcodeVersion
  }

  @objc public class var iosSDKVersionNumber: NSDecimalNumber {
    return NSDecimalNumber(string: iosSDKVersion)
  }

  @objc public class var iosSDKVersionNumberFormatter: NumberFormatter {
    return _iosSDKVersionNumberFormatter
  }

  @objc public class var iosSDKVersion: String {
    return _iosSDKVersion
  }

  @objc public class var isXcode12OrGreater: Bool {
    return xcodeVersionNumber.compare(NSDecimalNumber(string: "12.0")) != .orderedAscending
  }

  @objc public class var isXcode12_5OrGreater: Bool {
    return xcodeVersionNumber.compare(NSDecimalNumber(string: "12.5")) != .orderedAscending
  }

  @objc public class var simulatorApp: FBBundleDescriptor {
    do {
      return try FBBundleDescriptor.bundle(fromPath: simulatorApplicationPath)
    } catch {
      fatalError("Expected to be able to build an Application, got an error \(error)")
    }
  }

  @objc(getDeveloperDirectoryIfExists)
  public class func getDeveloperDirectoryIfExists() -> String? {
    return _developerDirectoryResult.directory
  }

  // MARK: NSObject

  override public class func description() -> String {
    return "Developer Directory \(developerDirectory) | Xcode Version \(xcodeVersionNumber) | iOS SDK Version \(iosSDKVersionNumber)"
  }

  public override var description: String {
    return Self.description()
  }

  // MARK: Private

  fileprivate class var simulatorApplicationPath: String {
    return ((developerDirectory as NSString).appendingPathComponent("Applications") as NSString).appendingPathComponent("Simulator.app")
  }

  fileprivate class var iPhoneSimulatorPlatformInfoPlistPath: String {
    return ((developerDirectory as NSString).appendingPathComponent("Platforms/iPhoneSimulator.platform") as NSString).appendingPathComponent("Info.plist")
  }

  fileprivate class var xcodeInfoPlistPath: String {
    return ((developerDirectory as NSString).deletingLastPathComponent as NSString).appendingPathComponent("Info.plist")
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

  private class func findXcodeDeveloperDirectoryOrAssert() -> String {
    guard let directory = _developerDirectoryResult.directory else {
      fatalError("Failed to get developer directory from xcode-select: \(_developerDirectoryResult.error?.description ?? "")")
    }
    return directory
  }
}
