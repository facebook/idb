/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

private let shimulatorFileName = "libShimulator-iOS.dylib"
private let maculatorShimFileName = "libShimulator-macOS.dylib"

private enum CanonicalShim: CaseIterable {
  case iOSSimulatorTest
  case macTest

  var filename: String {
    switch self {
    case .iOSSimulatorTest: return shimulatorFileName
    case .macTest: return maculatorShimFileName
    }
  }

  var codesigningRequired: Bool {
    switch self {
    case .iOSSimulatorTest: return FBControlCoreGlobalConfiguration.confirmCodesignaturesAreValid
    case .macTest: return false
    }
  }
}

public class FBXCTestShimConfiguration: NSObject, NSCopying {

  public let iOSSimulatorTestShimPath: String
  public let macOSTestShimPath: String

  // MARK: Initializers

  public init(iOSSimulatorTestShimPath: String, macOSTestShimPath: String) {
    assert(!iOSSimulatorTestShimPath.isEmpty)
    assert(!macOSTestShimPath.isEmpty)
    self.iOSSimulatorTestShimPath = iOSSimulatorTestShimPath
    self.macOSTestShimPath = macOSTestShimPath
    super.init()
  }

  private class func createWorkQueue() -> DispatchQueue {
    DispatchQueue(label: "com.facebook.xctestbootstrap.shims")
  }

  private class func pathForCanonicallyNamedShim(_ shim: CanonicalShim, inDirectory directory: String, logger: FBControlCoreLogger?) -> FBFuture<AnyObject> {
    let codesign = FBCodesignProvider.codeSignCommand(withIdentityName: "-", logger: nil)

    let shimPath = (directory as NSString).appendingPathComponent(shim.filename)
    if !FileManager.default.fileExists(atPath: shimPath) {
      return FBControlCoreError.describe("No shim located at expected location of \(shimPath)").failFuture()
    }
    if !shim.codesigningRequired {
      return FBFuture(result: shimPath as AnyObject)
    }
    return codesign.cdHashForBundle(atPath: shimPath)
      .rephraseFailure("Shim at path \(shimPath) was required to be signed, but it was not")
      .mapReplace(shimPath as AnyObject)
  }

  public class func findShimDirectory(onQueue queue: DispatchQueue, logger: FBControlCoreLogger?) -> FBFuture<NSString> {
    let future: FBFuture<AnyObject> = FBFuture.onQueue(
      queue,
      resolve: { () -> FBFuture<AnyObject> in
        guard let searchPath = BundledResources.directoryPath() else {
          return FBControlCoreError.describe("Unable to determine the shim search path.").failFuture()
        }

        let searchFuture: FBFuture<AnyObject> = confirmExistenceOfRequiredShims(inDirectory: searchPath, logger: logger)
        let shimNames = CanonicalShim.allCases.map(\.filename)
        return searchFuture.rephraseFailure("Could not find all shims \(FBCollectionInformation.oneLineDescription(from: shimNames)) in the expected directory \(searchPath)")
      })
    return unsafeBitCast(future, to: FBFuture<NSString>.self)
  }

  private class func confirmExistenceOfRequiredShims(inDirectory directory: String, logger: FBControlCoreLogger?) -> FBFuture<AnyObject> {
    if !FileManager.default.fileExists(atPath: directory) {
      return FBControlCoreError.describe("A shim directory was searched for at '\(directory)', but it was not there").failFuture()
    }
    let futures = CanonicalShim.allCases.map { pathForCanonicallyNamedShim($0, inDirectory: directory, logger: logger) }
    let combined = FBFuture<AnyObject>.combine(futures)
    return combined.mapReplace(directory as AnyObject)
  }

  nonisolated(unsafe) private static var _sharedShimFuture: FBFuture<FBXCTestShimConfiguration>?
  private static let _sharedShimLock = NSLock()

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

  public class func defaultShimConfiguration(with logger: FBControlCoreLogger?) -> FBFuture<FBXCTestShimConfiguration> {
    let queue = createWorkQueue()
    let future: FBFuture<AnyObject> = findShimDirectory(onQueue: queue, logger: logger)
      .onQueue(
        queue,
        fmap: { directory -> FBFuture<AnyObject> in
          shimConfiguration(withDirectory: directory as String, logger: logger).retyped(FBFuture<AnyObject>.self)
        })
    return unsafeBitCast(future, to: FBFuture<FBXCTestShimConfiguration>.self)
  }

  public class func shimConfiguration(withDirectory directory: String, logger: FBControlCoreLogger?) -> FBFuture<FBXCTestShimConfiguration> {
    let queue = createWorkQueue()
    let future: FBFuture<AnyObject> = confirmExistenceOfRequiredShims(inDirectory: directory, logger: logger)
      .onQueue(
        queue,
        fmap: { _ -> FBFuture<AnyObject> in
          let futures = [
            pathForCanonicallyNamedShim(.iOSSimulatorTest, inDirectory: directory, logger: logger),
            pathForCanonicallyNamedShim(.macTest, inDirectory: directory, logger: logger),
          ]
          return FBFuture<AnyObject>.combine(futures)
            .onQueue(
              queue,
              fmap: { shims -> FBFuture<AnyObject> in
                guard shims.count == 2,
                  let iOSSimulatorTestShimPath = shims[0] as? String,
                  let macOSTestShimPath = shims[1] as? String
                else {
                  return FBControlCoreError.describe("Expected the iOS simulator and macOS shim paths, got \(shims)").failFuture()
                }
                return FBFuture(result: FBXCTestShimConfiguration(iOSSimulatorTestShimPath: iOSSimulatorTestShimPath, macOSTestShimPath: macOSTestShimPath))
              })
        }
      )
    return unsafeBitCast(future, to: FBFuture<FBXCTestShimConfiguration>.self)
  }

  // MARK: NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    self
  }

  // MARK: NSObject

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBXCTestShimConfiguration else { return false }
    return iOSSimulatorTestShimPath == other.iOSSimulatorTestShimPath
      && macOSTestShimPath == other.macOSTestShimPath
  }

  public override var hash: Int {
    iOSSimulatorTestShimPath.hash ^ macOSTestShimPath.hash
  }
}
