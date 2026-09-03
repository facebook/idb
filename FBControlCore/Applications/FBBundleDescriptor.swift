/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The ways bundle inspection can fail, as data rather than assembled strings.
public enum FBBundleDescriptorError: Error {
  case binaryPathUnavailable(bundlePath: String)
  case bundleLoadFailed(path: String)
  case bundleIdentifierUnavailable(name: String, path: String)
  case noApplicationInIPA(presentFiles: [String])
  case multipleApplicationsInIPA(count: Int, found: [String])
}

extension FBBundleDescriptorError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .binaryPathUnavailable(bundlePath):
      return "Could not obtain binary path for bundle \(bundlePath)"
    case let .bundleLoadFailed(path):
      return "Failed to load bundle at path \(path)"
    case let .bundleIdentifierUnavailable(name, path):
      return "Could not obtain Bundle ID for bundle '\(name)' at \(path)"
    case let .noApplicationInIPA(presentFiles):
      return "Could not find an Application in IPA, present files \(FBCollectionInformation.oneLineDescription(from: presentFiles))"
    case let .multipleApplicationsInIPA(count, found):
      return "Expected only one Application in IPA, found \(count): \(FBCollectionInformation.oneLineDescription(from: found))"
    }
  }
}

@objc(FBBundleDescriptor)
public final class FBBundleDescriptor: NSObject, NSCopying, Sendable {

  @objc public let name: String
  @objc public let identifier: String
  @objc public let path: String
  @objc public let binary: FBBinaryDescriptor?

  // MARK: Initializers

  @objc
  public init(name: String, identifier: String, path: String, binary: FBBinaryDescriptor?) {
    self.name = name
    self.identifier = identifier
    self.path = path
    self.binary = binary
    super.init()
  }

  @objc(bundleFromPath:error:)
  public class func bundle(fromPath path: String) throws -> FBBundleDescriptor {
    return try bundleFromPath(path, fallbackIdentifier: false)
  }

  @objc(bundleWithFallbackIdentifierFromPath:error:)
  public class func bundleWithFallbackIdentifier(fromPath path: String) throws -> FBBundleDescriptor {
    return try bundleFromPath(path, fallbackIdentifier: true)
  }

  // MARK: NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    return self
  }

  // MARK: NSObject

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBBundleDescriptor, other.isMember(of: type(of: self)) else {
      return false
    }
    return other.name == name
      && other.path == path
      && other.identifier == identifier
      && (other.binary?.isEqual(binary) ?? (binary == nil))
  }

  public override var hash: Int {
    name.hash | path.hash | identifier.hash | (binary?.hash ?? 0)
  }

  public override var description: String {
    "Name: \(name) | ID: \(identifier)"
  }

  // MARK: Public Methods

  public func updatePathsForRelocation(withCodesign codesign: FBCodesignProvider, logger: FBControlCoreLogger) async throws {
    let replacements = try replacementsForBinary()
    if !replacements.isEmpty {
      var arguments: [String] = []
      for (key, value) in replacements {
        arguments.append("-rpath")
        arguments.append(key)
        arguments.append(value)
      }
      if let binaryPath = binary?.path {
        arguments.append(binaryPath)
      }
      logger.log("Updating rpaths for binary \(FBCollectionInformation.oneLineDescription(from: replacements as [String: Any]))")
      _ = try await bridgeFBFuture(
        FBProcessBuilder<AnyObject, AnyObject, AnyObject>
          .withLaunchPath("/usr/bin/install_name_tool", arguments: arguments)
          .withStdErr(to: logger)
          .runUntilCompletion(withAcceptableExitCodes: Set([0 as NSNumber])))
    }
    logger.log("Re-Codesigning after rpath update \(path)")
    try await bridgeFBFutureVoid(codesign.signBundle(atPath: path))
  }

  // MARK: Private

  private class func binaryForBundle(_ bundle: Bundle) throws -> FBBinaryDescriptor {
    guard let binaryPath = bundle.executablePath else {
      throw FBBundleDescriptorError.binaryPathUnavailable(bundlePath: bundle.bundlePath)
    }
    return try FBBinaryDescriptor.binary(withPath: binaryPath)
  }

  private class func bundleNameForBundle(_ bundle: Bundle) -> String {
    return (bundle.infoDictionary?["CFBundleName"] as? String)
      ?? (bundle.infoDictionary?["CFBundleExecutable"] as? String)
      ?? ((bundle.bundlePath as NSString).deletingPathExtension as NSString).lastPathComponent
  }

  private func replacementsForBinary() throws -> [String: String] {
    guard let rpaths = try binary?.rpaths() else {
      return [:]
    }
    return FBBundleDescriptor.interpolateRpathReplacements(forRPaths: rpaths)
  }

  private class func interpolateRpathReplacements(forRPaths rpaths: [String]) -> [String: String] {
    guard let regex = try? NSRegularExpression(pattern: "(/Applications/(?:xcode|Xcode).*\\.app/Contents/Developer)(.*)", options: []) else {
      return [:]
    }
    var replacements: [String: String] = [:]
    for rpath in rpaths {
      let result = regex.firstMatch(in: rpath, options: [], range: NSRange(location: 0, length: (rpath as NSString).length))
      guard let result else {
        continue
      }
      let oldXcodePath = (rpath as NSString).substring(with: result.range(at: 1))
      replacements[rpath] = rpath.replacingOccurrences(of: oldXcodePath, with: FBXcodeConfiguration.developerDirectory)
    }
    return replacements
  }

  private class func bundleFromPath(_ path: String, fallbackIdentifier: Bool) throws -> FBBundleDescriptor {
    guard let bundle = Bundle(path: path) else {
      throw FBBundleDescriptorError.bundleLoadFailed(path: path)
    }
    let bundleName = bundleNameForBundle(bundle)
    guard let identifier = bundle.bundleIdentifier ?? (fallbackIdentifier ? bundleName : nil) else {
      throw FBBundleDescriptorError.bundleIdentifierUnavailable(name: (path as NSString).lastPathComponent, path: path)
    }
    let binary = try binaryForBundle(bundle)
    return FBBundleDescriptor(name: bundleName, identifier: identifier, path: path, binary: binary)
  }
}
