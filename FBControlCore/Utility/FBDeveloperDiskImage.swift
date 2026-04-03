/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

private let ExtraDeviceSupportDirEnv = "IDB_EXTRA_DEVICE_SUPPORT_DIR"

private func scoreVersions(_ current: OperatingSystemVersion, _ target: OperatingSystemVersion) -> Int {
  let major = abs((current.majorVersion - target.majorVersion) * 10)
  let minor = abs(current.minorVersion - target.minorVersion)
  return major + minor
}

@objc(FBDeveloperDiskImage)
public class FBDeveloperDiskImage: NSObject {

  // MARK: Properties

  @objc public let diskImagePath: String
  @objc public let signature: Data
  @objc public let version: OperatingSystemVersion
  @objc public let xcodeVersion: OperatingSystemVersion

  // MARK: Private Init

  private init(diskImagePath: String, signature: Data, version: OperatingSystemVersion, xcodeVersion: OperatingSystemVersion) {
    self.diskImagePath = diskImagePath
    self.signature = signature
    self.version = version
    self.xcodeVersion = xcodeVersion
    super.init()
  }

  // MARK: Initializers

  @objc(unknownDiskImageWithSignature:)
  public class func unknownDiskImage(withSignature signature: Data) -> FBDeveloperDiskImage {
    let unknownVersion = OperatingSystemVersion(majorVersion: 0, minorVersion: 0, patchVersion: 0)
    return FBDeveloperDiskImage(diskImagePath: "unknown.dmg", signature: signature, version: unknownVersion, xcodeVersion: unknownVersion)
  }

  @objc(developerDiskImage:logger:error:)
  public class func developerDiskImage(_ targetVersion: OperatingSystemVersion, logger: (any FBControlCoreLogger)?) throws -> FBDeveloperDiskImage {
    let images = allDiskImages
    return try bestImage(forImages: images, targetVersion: targetVersion, logger: logger)
  }

  @objc public class var allDiskImages: [FBDeveloperDiskImage] {
    return _cachedAllDiskImages
  }

  nonisolated(unsafe) private static let _cachedAllDiskImages: [FBDeveloperDiskImage] = {
    let searchPath = (FBXcodeConfiguration.developerDirectory as NSString).appendingPathComponent("Platforms/iPhoneOS.platform/DeviceSupport")
    var images = allDiskImages(fromSearchPath: searchPath, xcodeVersion: FBXcodeConfiguration.xcodeVersion, logger: FBControlCoreGlobalConfiguration.defaultLogger)
    if ProcessInfo.processInfo.environment.keys.contains(ExtraDeviceSupportDirEnv) {
      let extraPath = ProcessInfo.processInfo.environment[ExtraDeviceSupportDirEnv]!
      let extraImages = allDiskImages(fromSearchPath: extraPath, xcodeVersion: FBXcodeConfiguration.xcodeVersion, logger: FBControlCoreGlobalConfiguration.defaultLogger)
      images = images + extraImages
    }
    return images
  }()

  // MARK: Public

  @objc(pathForDeveloperSymbols:logger:error:)
  public class func pathForDeveloperSymbols(_ buildVersion: String, logger: any FBControlCoreLogger) throws -> String {
    let searchPaths = [
      (NSHomeDirectory() as NSString).appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport"),
      (FBXcodeConfiguration.developerDirectory as NSString).appendingPathComponent("Platforms/iPhoneOS.platform/DeviceSupport"),
    ]
    logger.log("Attempting to find Symbols directory by build version \(buildVersion)")
    var paths: [String] = []
    for searchPath in searchPaths {
      guard let supportPaths = try? FileManager.default.contentsOfDirectory(atPath: searchPath) else {
        continue
      }
      for supportName in supportPaths {
        let supportPath = (searchPath as NSString).appendingPathComponent(supportName)
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: supportPath, isDirectory: &isDirectory) {
          continue
        }
        if !isDirectory.boolValue {
          continue
        }
        let symbolsPath = (supportPath as NSString).appendingPathComponent("Symbols")
        if !FileManager.default.fileExists(atPath: symbolsPath, isDirectory: &isDirectory) {
          continue
        }
        if !isDirectory.boolValue {
          continue
        }
        paths.append(symbolsPath)
      }
    }
    for path in paths {
      if path.contains(buildVersion) {
        return path
      }
    }
    throw FBControlCoreError.describe("Could not find the Symbols for \(buildVersion) in any of \(FBCollectionInformation.oneLineDescription(from: paths))").build()
  }

  @objc(bestImageForImages:targetVersion:logger:error:)
  public class func bestImage(forImages images: [FBDeveloperDiskImage], targetVersion: OperatingSystemVersion, logger: (any FBControlCoreLogger)?) throws -> FBDeveloperDiskImage {
    if images.isEmpty {
      throw FBControlCoreError.describe("No disk images provided").build()
    }

    let sorted = images.sorted { left, right in
      let leftDelta = scoreVersions(left.version, targetVersion)
      let rightDelta = scoreVersions(right.version, targetVersion)
      return leftDelta < rightDelta
    }

    let best = sorted[0]
    let bestVersion = best.version
    if bestVersion.majorVersion == targetVersion.majorVersion && bestVersion.minorVersion == targetVersion.minorVersion {
      logger?.log("Found the best match for \(targetVersion.majorVersion).\(targetVersion.minorVersion) at \(best)")
      return best
    }
    if bestVersion.majorVersion == targetVersion.majorVersion {
      logger?.log("Found the closest match for \(targetVersion.majorVersion).\(targetVersion.minorVersion) at \(best)")
      return best
    }
    throw FBControlCoreError.describe("The best match \(best) is not suitable for \(targetVersion.majorVersion).\(targetVersion.minorVersion)").build()
  }

  // MARK: NSObject

  override public var description: String {
    return "\(diskImagePath): \(version.majorVersion).\(version.minorVersion)"
  }

  @objc public func compare(_ other: FBDeveloperDiskImage) -> ComparisonResult {
    var comparison = NSNumber(value: version.majorVersion).compare(NSNumber(value: other.version.majorVersion))
    if comparison != .orderedSame { return comparison }
    comparison = NSNumber(value: version.minorVersion).compare(NSNumber(value: other.version.minorVersion))
    if comparison != .orderedSame { return comparison }
    return NSNumber(value: version.patchVersion).compare(NSNumber(value: other.version.patchVersion))
  }

  // MARK: Private

  private class func allDiskImages(fromSearchPath searchPath: String, xcodeVersion: OperatingSystemVersion, logger: any FBControlCoreLogger) -> [FBDeveloperDiskImage] {
    var images: [FBDeveloperDiskImage] = []
    logger.log("Attempting to find Disk Images at path \(searchPath)")
    let contents = (try? FileManager.default.contentsOfDirectory(atPath: searchPath)) ?? []
    for fileName in contents {
      let resolvedPath = (searchPath as NSString).appendingPathComponent(fileName)
      do {
        let image = try diskImage(atPath: resolvedPath, xcodeVersion: xcodeVersion)
        images.append(image)
      } catch {
        logger.log("\(error) does not contain a valid disk image")
      }
    }
    return images.sorted { $0.compare($1) == .orderedAscending }
  }

  private class func diskImage(atPath path: String, xcodeVersion: OperatingSystemVersion) throws -> FBDeveloperDiskImage {
    let diskImagePath = (path as NSString).appendingPathComponent("DeveloperDiskImage.dmg")
    if !FileManager.default.fileExists(atPath: diskImagePath) {
      throw FBControlCoreError.describe("Disk image does not exist at expected path \(diskImagePath)").build()
    }
    let signaturePath = diskImagePath + ".signature"
    guard let signature = try? Data(contentsOf: URL(fileURLWithPath: signaturePath)) else {
      throw FBControlCoreError.describe("Failed to load signature at \(signaturePath)").build()
    }
    let version = FBOSVersion.operatingSystemVersion(fromName: (path as NSString).lastPathComponent)
    return FBDeveloperDiskImage(diskImagePath: diskImagePath, signature: signature, version: version, xcodeVersion: xcodeVersion)
  }
}
