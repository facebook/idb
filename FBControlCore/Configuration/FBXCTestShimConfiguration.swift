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

// The stored paths are immutable `let`s, so instances are safe to share across
// concurrency domains even though the NSObject base prevents checked Sendable.
// patternlint-disable-next-line unchecked-sendable
public class FBXCTestShimConfiguration: NSObject, NSCopying, @unchecked Sendable {

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

  // MARK: Lookup

  private class func pathForCanonicallyNamedShim(_ shim: CanonicalShim, inDirectory directory: String) async throws -> String {
    let shimPath = (directory as NSString).appendingPathComponent(shim.filename)
    guard FileManager.default.fileExists(atPath: shimPath) else {
      throw FBControlCoreError.describe("No shim located at expected location of \(shimPath)").build()
    }
    guard shim.codesigningRequired else {
      return shimPath
    }
    let codesign = FBCodesignProvider.codeSignCommand(withIdentityName: "-", logger: nil)
    do {
      _ = try await bridgeFBFuture(codesign.cdHashForBundle(atPath: shimPath))
    } catch {
      throw
        FBControlCoreError
        .describe("Shim at path \(shimPath) was required to be signed, but it was not")
        .caused(by: error as NSError)
        .build()
    }
    return shimPath
  }

  public class func findShimDirectory() async throws -> String {
    guard let searchPath = BundledResources.directoryPath() else {
      throw FBControlCoreError.describe("Unable to determine the shim search path.").build()
    }
    do {
      return try await confirmExistenceOfRequiredShims(inDirectory: searchPath)
    } catch {
      let shimNames = CanonicalShim.allCases.map(\.filename)
      throw
        FBControlCoreError
        .describe("Could not find all shims \(FBCollectionInformation.oneLineDescription(from: shimNames)) in the expected directory \(searchPath)")
        .caused(by: error as NSError)
        .build()
    }
  }

  private class func confirmExistenceOfRequiredShims(inDirectory directory: String) async throws -> String {
    guard FileManager.default.fileExists(atPath: directory) else {
      throw FBControlCoreError.describe("A shim directory was searched for at '\(directory)', but it was not there").build()
    }
    async let iOSSimulatorShim = pathForCanonicallyNamedShim(.iOSSimulatorTest, inDirectory: directory)
    async let macShim = pathForCanonicallyNamedShim(.macTest, inDirectory: directory)
    _ = try await (iOSSimulatorShim, macShim)
    return directory
  }

  // Caches the first resolution for the life of the process, matching the future the
  // old implementation memoised. An actor holding the task needs no lock and no
  // unsafely-nonisolated storage; concurrent first callers race to create the task
  // inside the actor, so exactly one resolution ever runs.
  private actor SharedResolution {
    private var task: Task<FBXCTestShimConfiguration, Error>?

    func configuration() async throws -> FBXCTestShimConfiguration {
      if let task {
        return try await task.value
      }
      let task = Task { try await FBXCTestShimConfiguration.defaultShimConfiguration() }
      self.task = task
      return try await task.value
    }
  }

  private static let sharedResolution = SharedResolution()

  public class func sharedShimConfiguration() async throws -> FBXCTestShimConfiguration {
    try await sharedResolution.configuration()
  }

  public class func defaultShimConfiguration() async throws -> FBXCTestShimConfiguration {
    let directory = try await findShimDirectory()
    return try await shimConfiguration(withDirectory: directory)
  }

  public class func shimConfiguration(withDirectory directory: String) async throws -> FBXCTestShimConfiguration {
    _ = try await confirmExistenceOfRequiredShims(inDirectory: directory)
    async let iOSSimulatorTestShimPath = pathForCanonicallyNamedShim(.iOSSimulatorTest, inDirectory: directory)
    async let macOSTestShimPath = pathForCanonicallyNamedShim(.macTest, inDirectory: directory)
    return try await FBXCTestShimConfiguration(
      iOSSimulatorTestShimPath: iOSSimulatorTestShimPath,
      macOSTestShimPath: macOSTestShimPath)
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
