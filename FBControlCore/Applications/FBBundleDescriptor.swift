/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBBundleDescriptor)
public class FBBundleDescriptor: NSObject, NSCopying {

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
      && (other.binary?.isEqual(binary) ?? false)
  }

  public override var hash: Int {
    return name.hash | path.hash | identifier.hash | (binary?.hash ?? 0)
  }

  public override var description: String {
    return "Name: \(name) | ID: \(identifier)"
  }

  // MARK: Public Methods

  @objc(updatePathsForRelocationWithCodesign:logger:queue:)
  public func updatePathsForRelocation(withCodesign codesign: FBCodesignProvider, logger: FBControlCoreLogger, queue: DispatchQueue) -> FBFuture<AnyObject> {
    return replacementsForBinary()
      .onQueue(
        queue,
        fmap: { (result: AnyObject) -> FBFuture<AnyObject> in
          let replacements = result as! NSDictionary as! [String: String]
          if replacements.isEmpty {
            return FBFuture(result: replacements as NSDictionary)
          }
          var arguments: [String] = []
          for key in replacements.keys {
            arguments.append("-rpath")
            arguments.append(key)
            arguments.append(replacements[key]!)
          }
          if let binaryPath = self.binary?.path {
            arguments.append(binaryPath)
          }
          logger.log("Updating rpaths for binary \(FBCollectionInformation.oneLineDescription(from: replacements as [String: Any]))")
          return
            FBProcessBuilder<AnyObject, AnyObject, AnyObject>
            .withLaunchPath("/usr/bin/install_name_tool", arguments: arguments)
            .withStdErr(to: logger)
            .runUntilCompletion(withAcceptableExitCodes: Set([0 as NSNumber]))
            .mapReplace(replacements as NSDictionary)
        }
      )
      .onQueue(
        queue,
        fmap: { (result: AnyObject) -> FBFuture<AnyObject> in
          let replacements = result as! NSDictionary
          logger.log("Re-Codesigning after rpath update \(self.path)")
          return codesign.signBundle(atPath: self.path).mapReplace(replacements)
        })
  }

  // MARK: Private

  private class func binaryForBundle(_ bundle: Bundle) throws -> FBBinaryDescriptor {
    guard let binaryPath = bundle.executablePath else {
      throw FBControlCoreError.describe("Could not obtain binary path for bundle \(bundle.bundlePath)").build()
    }
    return try FBBinaryDescriptor.binary(withPath: binaryPath)
  }

  private class func bundleNameForBundle(_ bundle: Bundle) -> String {
    return (bundle.infoDictionary?["CFBundleName"] as? String)
      ?? (bundle.infoDictionary?["CFBundleExecutable"] as? String)
      ?? ((bundle.bundlePath as NSString).deletingPathExtension as NSString).lastPathComponent
  }

  private func replacementsForBinary() -> FBFuture<AnyObject> {
    do {
      let rpaths = try binary?.rpaths()
      guard let rpaths = rpaths else {
        return FBFuture(result: NSDictionary())
      }
      return FBFuture(result: FBBundleDescriptor.interpolateRpathReplacements(forRPaths: rpaths) as NSDictionary)
    } catch {
      return FBFuture(error: error)
    }
  }

  private class func interpolateRpathReplacements(forRPaths rpaths: [String]) -> [String: String] {
    guard let regex = try? NSRegularExpression(pattern: "(/Applications/(?:xcode|Xcode).*\\.app/Contents/Developer)(.*)", options: []) else {
      return [:]
    }
    var replacements: [String: String] = [:]
    for rpath in rpaths {
      let result = regex.firstMatch(in: rpath, options: [], range: NSRange(location: 0, length: (rpath as NSString).length))
      guard let result = result else {
        continue
      }
      let oldXcodePath = (rpath as NSString).substring(with: result.range(at: 1))
      replacements[rpath] = rpath.replacingOccurrences(of: oldXcodePath, with: FBXcodeConfiguration.developerDirectory)
    }
    return replacements
  }

  private class func bundleFromPath(_ path: String, fallbackIdentifier: Bool) throws -> FBBundleDescriptor {
    guard let bundle = Bundle(path: path) else {
      throw FBControlCoreError.describe("Failed to load bundle at path \(path)").build()
    }
    let bundleName = bundleNameForBundle(bundle)
    var identifier = bundle.bundleIdentifier
    if identifier == nil {
      if !fallbackIdentifier {
        throw FBControlCoreError.describe("Could not obtain Bundle ID for bundle '\((path as NSString).lastPathComponent)' at \(path)").build()
      }
      identifier = bundleName
    }
    let binary = try binaryForBundle(bundle)
    return FBBundleDescriptor(name: bundleName, identifier: identifier!, path: path, binary: binary)
  }
}
