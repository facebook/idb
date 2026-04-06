/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

private let keySimulatorTestShim = "ios_simulator_test_shim"
private let keyMacTestShim = "mac_test_shim"

private let shimulatorFileName = "libShimulator.dylib"
private let maculatorShimFileName = "libMaculator.dylib"

/// Helper to call [FBFuture futureWithFutures:] which is NS_SWIFT_UNAVAILABLE.
private func combineFutures(_ futures: [FBFuture<AnyObject>]) -> FBFuture<AnyObject> {
  let sel = NSSelectorFromString("futureWithFutures:")
  let method = FBFuture<AnyObject>.method(for: sel)
  typealias Signature = @convention(c) (AnyObject, Selector, NSArray) -> FBFuture<AnyObject>
  let impl = unsafeBitCast(method, to: Signature.self)
  return impl(FBFuture<AnyObject>.self, sel, futures as NSArray)
}

@objc(FBXCTestShimConfiguration)
public class FBXCTestShimConfiguration: NSObject, NSCopying {

  @objc public let iOSSimulatorTestShimPath: String
  @objc public let macOSTestShimPath: String

  // MARK: Initializers

  @objc
  public init(iOSSimulatorTestShimPath: String, macOSTestShimPath: String) {
    assert(!iOSSimulatorTestShimPath.isEmpty)
    assert(!macOSTestShimPath.isEmpty)
    self.iOSSimulatorTestShimPath = iOSSimulatorTestShimPath
    self.macOSTestShimPath = macOSTestShimPath
    super.init()
  }

  private class func createWorkQueue() -> DispatchQueue {
    return DispatchQueue(label: "com.facebook.xctestbootstrap.shims")
  }

  private class var canonicalShimNameToShimFilenames: [String: String] {
    return [
      keySimulatorTestShim: shimulatorFileName,
      keyMacTestShim: maculatorShimFileName,
    ]
  }

  private class var canonicalShimNameToCodesigningRequired: [String: Bool] {
    return [
      keySimulatorTestShim: FBControlCoreGlobalConfiguration.confirmCodesignaturesAreValid,
      keyMacTestShim: false,
    ]
  }

  private class func pathForCanonicallyNamedShim(_ canonicalName: String, inDirectory directory: String, logger: FBControlCoreLogger?) -> FBFuture<AnyObject> {
    let filename = canonicalShimNameToShimFilenames[canonicalName]!
    let codesign = FBCodesignProvider.codeSignCommand(withIdentityName: "-", logger: nil)
    let signingRequired = canonicalShimNameToCodesigningRequired[canonicalName]!

    let shimPath = (directory as NSString).appendingPathComponent(filename)
    if !FileManager.default.fileExists(atPath: shimPath) {
      return FBControlCoreError.describe("No shim located at expected location of \(shimPath)").failFuture()
    }
    if !signingRequired {
      return FBFuture(result: shimPath as AnyObject)
    }
    return codesign.cdHashForBundle(atPath: shimPath)
      .rephraseFailure("Shim at path \(shimPath) was required to be signed, but it was not")
      .mapReplace(shimPath as AnyObject)
  }

  @objc
  public class func findShimDirectory(onQueue queue: DispatchQueue, logger: FBControlCoreLogger?) -> FBFuture<NSString> {
    let future: FBFuture<AnyObject> = FBFuture.onQueue(queue, resolve: { () -> FBFuture<AnyObject> in
      var searchPaths: [String] = []
      let environmentDefinedDirectory = ProcessInfo.processInfo.environment[FBXCTestShimDirectoryEnvironmentOverride]
      if let envDir = environmentDefinedDirectory {
        searchPaths.append(envDir)
      } else {
        if let root = fbxctestInstallationRoot {
          searchPaths.append((root as NSString).appendingPathComponent("lib"))
          searchPaths.append((root as NSString).appendingPathComponent("bin"))
          searchPaths.append((root as NSString).appendingPathComponent("idb"))
          searchPaths.append((root as NSString).appendingPathComponent("idb/bin"))
        }
        if let resourcePath = Bundle(for: self).resourcePath {
          searchPaths.append(resourcePath)
        }
      }

      var futures: [FBFuture<AnyObject>] = []
      for path in searchPaths {
        let f: FBFuture<AnyObject> = confirmExistenceOfRequiredShims(inDirectory: path, logger: logger)
        futures.append(f.fallback("" as AnyObject))
      }
      let combined = combineFutures(futures)
      return combined.onQueue(queue, fmap: { result -> FBFuture<AnyObject> in
        let paths = result as! [String]
        for path in paths {
          if path.isEmpty {
            continue
          }
          return FBFuture(result: path as AnyObject)
        }
        let shimNames = Array(self.canonicalShimNameToShimFilenames.values)
        return FBControlCoreError.describe("Could not find all shims \(FBCollectionInformation.oneLineDescription(from: shimNames)) in any of the expected directories \(FBCollectionInformation.oneLineDescription(from: searchPaths))").failFuture()
      })
    })
    return unsafeBitCast(future, to: FBFuture<NSString>.self)
  }

  private class func confirmExistenceOfRequiredShims(inDirectory directory: String, logger: FBControlCoreLogger?) -> FBFuture<AnyObject> {
    if !FileManager.default.fileExists(atPath: directory) {
      return FBControlCoreError.describe("A shim directory was searched for at '\(directory)', but it was not there").failFuture()
    }
    var futures: [FBFuture<AnyObject>] = []
    for canonicalName in canonicalShimNameToShimFilenames.keys {
      futures.append(pathForCanonicallyNamedShim(canonicalName, inDirectory: directory, logger: logger))
    }
    let combined = combineFutures(futures)
    return combined.mapReplace(directory as AnyObject)
  }

  nonisolated(unsafe) private static var _sharedShimFuture: FBFuture<FBXCTestShimConfiguration>?
  private static let _sharedShimLock = NSLock()

  @objc(sharedShimConfigurationWithLogger:)
  public class func sharedShimConfiguration(with logger: FBControlCoreLogger?) -> FBFuture<FBXCTestShimConfiguration> {
    _sharedShimLock.lock()
    defer { _sharedShimLock.unlock() }
    if let existing = _sharedShimFuture {
      return existing
    }
    let result = defaultShimConfiguration(with: logger)
    _sharedShimFuture = result
    return result
  }

  @objc
  public class func defaultShimConfiguration(with logger: FBControlCoreLogger?) -> FBFuture<FBXCTestShimConfiguration> {
    let queue = createWorkQueue()
    let future: FBFuture<AnyObject> = (findShimDirectory(onQueue: queue, logger: logger) as! FBFuture<AnyObject>)
      .onQueue(queue, fmap: { result -> FBFuture<AnyObject> in
        let directory = result as! String
        return shimConfiguration(withDirectory: directory, logger: logger) as! FBFuture<AnyObject>
      })
    return unsafeBitCast(future, to: FBFuture<FBXCTestShimConfiguration>.self)
  }

  @objc
  public class func shimConfiguration(withDirectory directory: String, logger: FBControlCoreLogger?) -> FBFuture<FBXCTestShimConfiguration> {
    let queue = createWorkQueue()
    let future: FBFuture<AnyObject> = confirmExistenceOfRequiredShims(inDirectory: directory, logger: logger)
      .onQueue(queue, fmap: { result -> FBFuture<AnyObject> in
        let shimDirectory = result as! String
        let futures: [FBFuture<AnyObject>] = [
          pathForCanonicallyNamedShim(keySimulatorTestShim, inDirectory: shimDirectory, logger: logger),
          pathForCanonicallyNamedShim(keyMacTestShim, inDirectory: shimDirectory, logger: logger),
        ]
        return combineFutures(futures)
      })
      .onQueue(queue, map: { result -> AnyObject in
        let shims = result as! [String]
        return FBXCTestShimConfiguration(iOSSimulatorTestShimPath: shims[0], macOSTestShimPath: shims[1])
      })
    return unsafeBitCast(future, to: FBFuture<FBXCTestShimConfiguration>.self)
  }

  private class var fbxctestInstallationRoot: String? {
    var executablePath = ProcessInfo.processInfo.arguments[0]
    if !(executablePath as NSString).isAbsolutePath {
      executablePath = (FileManager.default.currentDirectoryPath as NSString).appending(executablePath)
    }
    executablePath = (executablePath as NSString).standardizingPath
    let path = ((executablePath as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
    return FileManager.default.fileExists(atPath: path) ? path : nil
  }

  // MARK: NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    return self
  }

  // MARK: NSObject

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBXCTestShimConfiguration else { return false }
    return iOSSimulatorTestShimPath == other.iOSSimulatorTestShimPath
      && macOSTestShimPath == other.macOSTestShimPath
  }

  public override var hash: Int {
    return iOSSimulatorTestShimPath.hash ^ macOSTestShimPath.hash
  }
}
