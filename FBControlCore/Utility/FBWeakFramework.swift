/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The ways weak-framework loading can fail, as data rather than assembled strings.
public enum FBWeakFrameworkError: Error {
  case missingRequiredClass(className: String, frameworkName: String)
  case rootUserForbidden(relativePath: String)
  case fileMissing(path: String)
  case bundleLoadFailed(path: String)
  case bundleUnavailable(className: String)
  case loadedFromWrongDirectory(frameworkName: String, bundlePath: String, basePath: String)
}

extension FBWeakFrameworkError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .missingRequiredClass(className, frameworkName):
      return "Missing \(className) class from \(frameworkName) framework"
    case let .rootUserForbidden(relativePath):
      return "\(relativePath) cannot be loaded from the root user. Don't run this as root."
    case let .fileMissing(path):
      return "Attempting to load a file at path '\(path)', but it does not exist"
    case let .bundleLoadFailed(path):
      return "Failed to load the bundle for path \(path)"
    case let .bundleUnavailable(className):
      return "Could not obtain Framework bundle for class named \(className)"
    case let .loadedFromWrongDirectory(frameworkName, bundlePath, basePath):
      return "Expected Framework \(frameworkName) to be loaded for Developer Directory at path \(bundlePath), but was loaded from \(basePath)"
    }
  }
}

@objc(FBWeakFramework)
public class FBWeakFramework: NSObject {

  // MARK: Properties

  @objc public let name: String
  private let basePath: String
  private let relativePath: String
  private let requiredClassNames: [String]
  private let rootPermitted: Bool

  // MARK: Factory Methods

  @objc(xcodeFrameworkWithRelativePath:requiredClassNames:)
  public class func xcodeFramework(withRelativePath relativePath: String, requiredClassNames: [String]) -> FBWeakFramework {
    FBWeakFramework(
      basePath: FBXcodeConfiguration.developerDirectory,
      relativePath: relativePath,
      requiredClassNames: requiredClassNames,
      rootPermitted: false
    )
  }

  @objc(frameworkWithPath:requiredClassNames:rootPermitted:)
  public class func framework(withPath absolutePath: String, requiredClassNames: [String], rootPermitted: Bool) -> FBWeakFramework {
    FBWeakFramework(
      basePath: absolutePath,
      relativePath: "",
      requiredClassNames: requiredClassNames,
      rootPermitted: rootPermitted
    )
  }

  // MARK: Private Init

  private init(basePath: String, relativePath: String, requiredClassNames: [String], rootPermitted: Bool) {
    let fullPath = (basePath as NSString).appendingPathComponent(relativePath)
    let filename = (fullPath as NSString).lastPathComponent
    self.name = (filename as NSString).deletingPathExtension
    self.basePath = basePath
    self.relativePath = relativePath
    self.requiredClassNames = requiredClassNames
    self.rootPermitted = rootPermitted
    super.init()
  }

  // MARK: Public Methods

  /// `logger` is optional: the Objective-C loaders that call this vend a nullable logger, and a
  /// process that has not configured one loads frameworks silently rather than trapping.
  @objc(loadWithLogger:error:)
  public func load(with logger: (any FBControlCoreLogger)?) throws {
    try loadFromRelativeDirectory(basePath, logger: logger)
  }

  // MARK: Private

  private func allRequiredClassesExist() throws {
    for requiredClassName in requiredClassNames {
      if NSClassFromString(requiredClassName) == nil {
        throw FBWeakFrameworkError.missingRequiredClass(className: requiredClassName, frameworkName: name)
      }
    }
  }

  private func loadFromRelativeDirectory(_ relativeDirectory: String, logger: (any FBControlCoreLogger)?) throws {
    // Check if classes are already loaded
    if (try? allRequiredClassesExist()) != nil && !requiredClassNames.isEmpty {
      logger?.debug().log("\(name): Already loaded, skipping")
      try verifyIfLoaded(with: logger)
      return
    }

    // Check root permission
    if NSUserName() == "root" && !rootPermitted {
      throw FBWeakFrameworkError.rootUserForbidden(relativePath: relativePath)
    }

    // Load framework
    let path = ((relativeDirectory as NSString).appendingPathComponent(relativePath) as NSString).standardizingPath
    if !FileManager.default.fileExists(atPath: path) {
      throw FBWeakFrameworkError.fileMissing(path: path)
    }

    guard let bundle = Bundle(path: path) else {
      throw FBWeakFrameworkError.bundleLoadFailed(path: path)
    }

    logger?.debug().log("\(name): Loading from \(path) ")
    try bundle.loadAndReturnError()

    logger?.debug().log("\(name): Successfully loaded")
    try allRequiredClassesExist()
    try verifyIfLoaded(with: logger)
  }

  private func verifyIfLoaded(with logger: (any FBControlCoreLogger)?) throws {
    for requiredClassName in requiredClassNames {
      try verifyRelativeDirectory(forPrivateClass: requiredClassName, logger: logger)
    }
  }

  private func verifyRelativeDirectory(forPrivateClass className: String, logger: (any FBControlCoreLogger)?) throws {
    guard let cls = NSClassFromString(className) else {
      throw FBWeakFrameworkError.bundleUnavailable(className: className)
    }
    let bundle = Bundle(for: cls)

    // Developer Directory is: /Applications/Xcode.app/Contents/Developer
    // The common base path is: /Applications/Xcode.app
    let commonBasePath = ((basePath as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
    if !bundle.bundlePath.hasPrefix(commonBasePath) {
      throw FBWeakFrameworkError.loadedFromWrongDirectory(frameworkName: (bundle.bundlePath as NSString).lastPathComponent, bundlePath: bundle.bundlePath, basePath: basePath)
    }
    logger?.debug().log("\(name): \(className) has correct path of \(commonBasePath)")
  }
}
