/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBXcodeConfiguration)
public class FBXcodeConfiguration: NSObject {

  // MARK: Injected Developer Directory (fork addition)

  // Sandboxed hosts (e.g. Mac App Store apps) cannot invoke `xcode-select` or
  // read `/var/db/xcode_select_link`, so they inject the developer directory
  // resolved from a security-scoped bookmark instead. All derived values are
  // cached and reset on injection so hosts that switch Xcode at runtime pick
  // up the new directory without a restart. This mirrors the pre-rewrite
  // Objective-C implementation of this class.
  //
  // The lock only guards the cache storage; derived values are computed
  // outside the lock because their computation reads `developerDirectory`,
  // which takes the same (non-recursive) lock.
  private static let cacheLock = NSLock()
  nonisolated(unsafe) private static var injectedDeveloperDirectory: String?
  nonisolated(unsafe) private static var cachedDeveloperDirectory: String??
  nonisolated(unsafe) private static var cachedXcodeVersionNumber: NSDecimalNumber?
  nonisolated(unsafe) private static var cachedIOSSDKVersion: String?

  /**
   Injects the Xcode developer directory to use, bypassing `xcode-select` resolution.
   Overrides the resolved developer directory until cleared with nil.
   */
  @objc public static func setInjectedDeveloperDirectory(_ developerDirectory: String?) {
    cacheLock.withLock {
      injectedDeveloperDirectory = developerDirectory
      cachedDeveloperDirectory = nil
      cachedXcodeVersionNumber = nil
      cachedIOSSDKVersion = nil
    }
  }

  // MARK: Public Properties

  @objc public static var developerDirectory: String {
    resolvedDeveloperDirectory() ?? ""
  }

  /// The developer directory if it can be resolved, nil otherwise.
  @objc public static func getDeveloperDirectoryIfExists() -> String? {
    resolvedDeveloperDirectory()
  }

  @objc public static var contentsDirectory: String {
    (developerDirectory as NSString).deletingLastPathComponent
  }

  @objc public static var xcodeVersionNumber: NSDecimalNumber {
    if let cached = cacheLock.withLock({ cachedXcodeVersionNumber }) {
      return cached
    }
    let versionString = FBXcodeConfiguration.readValue(forKey: "CFBundleShortVersionString", fromPlistAtPath: FBXcodeConfiguration.xcodeInfoPlistPath)
    let versionNumber = NSDecimalNumber(string: versionString as? String)
    cacheLock.withLock { cachedXcodeVersionNumber = versionNumber }
    return versionNumber
  }

  @objc public static var xcodeVersion: OperatingSystemVersion {
    FBOSVersion.operatingSystemVersion(fromName: xcodeVersionNumber.stringValue)
  }

  @objc public static var iosSDKVersionNumber: NSDecimalNumber {
    NSDecimalNumber(string: iosSDKVersion)
  }

  @objc public static let iosSDKVersionNumberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 1
    formatter.maximumFractionDigits = 3
    return formatter
  }()

  @objc public static var iosSDKVersion: String {
    if let cached = cacheLock.withLock({ cachedIOSSDKVersion }) {
      return cached
    }
    let version = FBXcodeConfiguration.readValue(forKey: "Version", fromPlistAtPath: FBXcodeConfiguration.iPhoneSimulatorPlatformInfoPlistPath) as? String ?? ""
    cacheLock.withLock { cachedIOSSDKVersion = version }
    return version
  }

  @objc public static var isXcode12OrGreater: Bool {
    xcodeVersionNumber.compare(NSDecimalNumber(string: "12.0")) != .orderedAscending
  }

  @objc public static var isXcode12_5OrGreater: Bool {
    xcodeVersionNumber.compare(NSDecimalNumber(string: "12.5")) != .orderedAscending
  }

  @objc public static var simulatorApp: FBBundleDescriptor {
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
  }

  // MARK: NSObject

  override public class func description() -> String {
    "Developer Directory \(developerDirectory) | Xcode Version \(xcodeVersionNumber) | iOS SDK Version \(iosSDKVersionNumber)"
  }

  public override var description: String {
    Self.description()
  }

  // MARK: Private

  private static func resolvedDeveloperDirectory() -> String? {
    let cached: String?? = cacheLock.withLock {
      if let injected = injectedDeveloperDirectory {
        return .some(injected)
      }
      return cachedDeveloperDirectory
    }
    if let cached {
      return cached
    }
    let resolved = try? FBXcodeDirectory.resolveDeveloperDirectory()
    cacheLock.withLock {
      // An injection may have raced this resolution; do not clobber it.
      if injectedDeveloperDirectory == nil, cachedDeveloperDirectory == nil {
        cachedDeveloperDirectory = .some(resolved)
      }
    }
    return resolved
  }

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
