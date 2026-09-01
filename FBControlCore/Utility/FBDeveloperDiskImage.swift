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

/// The ways disk-image discovery can fail, as data rather than assembled strings.
public enum FBDeveloperDiskImageError: Error {
  case symbolsNotFound(buildVersion: String, searched: [String])
  case noImagesProvided
  case noSuitableImage(bestDescription: String, majorVersion: Int, minorVersion: Int)
  case imageMissing(path: String)
  case signatureLoadFailed(path: String)
}

extension FBDeveloperDiskImageError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .symbolsNotFound(buildVersion, searched):
      return "Could not find the Symbols for \(buildVersion) in any of \(FBCollectionInformation.oneLineDescription(from: searched))"
    case .noImagesProvided:
      return "No disk images provided"
    case let .noSuitableImage(bestDescription, majorVersion, minorVersion):
      return "The best match \(bestDescription) is not suitable for \(majorVersion).\(minorVersion)"
    case let .imageMissing(path):
      return "Disk image does not exist at expected path \(path)"
    case let .signatureLoadFailed(path):
      return "Failed to load signature at \(path)"
    }
  }
}

/// Where the developer disk images available on this host come from.
///
/// Exists so a caller can be handed a known set instead of whatever Xcode has installed, which is
/// otherwise the one input to disk image selection that cannot be supplied.
public protocol DeveloperDiskImageProviding {
  var availableDiskImages: [FBDeveloperDiskImage] { get }
}

/// The default: the images in the device support directories of the selected Xcode, plus any in
/// `IDB_EXTRA_DEVICE_SUPPORT_DIR`.
public struct InstalledDeveloperDiskImages: DeveloperDiskImageProviding {
  public init() {}

  /// Scanned once per process. The directories do not change under a running companion, and the
  /// scan stats every candidate directory and reads a signature from each.
  public var availableDiskImages: [FBDeveloperDiskImage] {
    Self.scanned
  }

  private static let scanned: [FBDeveloperDiskImage] = {
    let xcodeVersion = FBXcodeConfiguration.xcodeVersion
    let logger = FBControlCoreGlobalConfiguration.defaultLogger
    let searchPath = (FBXcodeConfiguration.developerDirectory as NSString).appendingPathComponent("Platforms/iPhoneOS.platform/DeviceSupport")
    var found = InstalledDeveloperDiskImages.images(inDirectory: searchPath, xcodeVersion: xcodeVersion, logger: logger)
    if let extraPath = ProcessInfo.processInfo.environment[ExtraDeviceSupportDirEnv] {
      found += InstalledDeveloperDiskImages.images(inDirectory: extraPath, xcodeVersion: xcodeVersion, logger: logger)
    }
    return found
  }()

  private static func images(
    inDirectory searchPath: String,
    xcodeVersion: OperatingSystemVersion,
    logger: any FBControlCoreLogger
  ) -> [FBDeveloperDiskImage] {
    var images: [FBDeveloperDiskImage] = []
    logger.log("Attempting to find Disk Images at path \(searchPath)")
    let contents = (try? FileManager.default.contentsOfDirectory(atPath: searchPath)) ?? []
    for fileName in contents {
      let resolvedPath = (searchPath as NSString).appendingPathComponent(fileName)
      do {
        images.append(try diskImage(atPath: resolvedPath, xcodeVersion: xcodeVersion))
      } catch {
        logger.log("\(error) does not contain a valid disk image")
      }
    }
    return images.sorted { $0.compare($1) == .orderedAscending }
  }

  private static func diskImage(atPath path: String, xcodeVersion: OperatingSystemVersion) throws -> FBDeveloperDiskImage {
    let diskImagePath = (path as NSString).appendingPathComponent("DeveloperDiskImage.dmg")
    if !FileManager.default.fileExists(atPath: diskImagePath) {
      throw FBDeveloperDiskImageError.imageMissing(path: diskImagePath)
    }
    let signaturePath = diskImagePath + ".signature"
    guard let signature = try? Data(contentsOf: URL(fileURLWithPath: signaturePath)) else {
      throw FBDeveloperDiskImageError.signatureLoadFailed(path: signaturePath)
    }
    let version = FBOSVersion.operatingSystemVersion(fromName: (path as NSString).lastPathComponent)
    return FBDeveloperDiskImage(diskImagePath: diskImagePath, signature: signature, version: version, xcodeVersion: xcodeVersion)
  }
}

@objc(FBDeveloperDiskImage)
public final class FBDeveloperDiskImage: NSObject, @unchecked Sendable {

  // MARK: Properties

  @objc public let diskImagePath: String
  @objc public let signature: Data
  @objc public let version: OperatingSystemVersion
  @objc public let xcodeVersion: OperatingSystemVersion

  // MARK: Init

  /// Describes an image directly, rather than reading one out of a device support directory.
  ///
  /// Public because the tests that exercise image selection live in another module. Production
  /// code has no reason to call it: an image there always comes from a provider.
  public init(diskImagePath: String, signature: Data, version: OperatingSystemVersion, xcodeVersion: OperatingSystemVersion) {
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
    throw FBDeveloperDiskImageError.symbolsNotFound(buildVersion: buildVersion, searched: paths)
  }

  @objc(bestImageForImages:targetVersion:logger:error:)
  public class func bestImage(forImages images: [FBDeveloperDiskImage], targetVersion: OperatingSystemVersion, logger: (any FBControlCoreLogger)?) throws -> FBDeveloperDiskImage {
    if images.isEmpty {
      throw FBDeveloperDiskImageError.noImagesProvided
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
    throw FBDeveloperDiskImageError.noSuitableImage(bestDescription: String(describing: best), majorVersion: targetVersion.majorVersion, minorVersion: targetVersion.minorVersion)
  }

  // MARK: NSObject

  override public var description: String {
    "\(diskImagePath): \(version.majorVersion).\(version.minorVersion)"
  }

  @objc public func compare(_ other: FBDeveloperDiskImage) -> ComparisonResult {
    var comparison = NSNumber(value: version.majorVersion).compare(NSNumber(value: other.version.majorVersion))
    if comparison != .orderedSame { return comparison }
    comparison = NSNumber(value: version.minorVersion).compare(NSNumber(value: other.version.minorVersion))
    if comparison != .orderedSame { return comparison }
    return NSNumber(value: version.patchVersion).compare(NSNumber(value: other.version.patchVersion))
  }

}
