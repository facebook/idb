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

public enum FBXCTestShimError: Error {
  case shimMissing(path: String)
  case shimUnsigned(path: String, underlying: Error)
  case searchPathUnresolvable
  case shimDirectoryMissing(directory: String)
  case shimsMissingInDirectory(shimNames: [String], directory: String, underlying: Error)
}

extension FBXCTestShimError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .shimMissing(path):
      return "No shim located at expected location of \(path)"
    case let .shimUnsigned(path, _):
      return "Shim at path \(path) was required to be signed, but it was not"
    case .searchPathUnresolvable:
      return "Unable to determine the shim search path."
    case let .shimDirectoryMissing(directory):
      return "A shim directory was searched for at '\(directory)', but it was not there"
    case let .shimsMissingInDirectory(shimNames, directory, underlying):
      return "Could not find all shims \(FBCollectionInformation.oneLineDescription(from: shimNames)) in the expected directory \(directory): \(underlying.localizedDescription)"
    }
  }
}

public struct FBXCTestShimConfiguration: Sendable {

  public let iOSSimulatorTestShimPath: String
  public let macOSTestShimPath: String

  // MARK: Initializers

  public init(iOSSimulatorTestShimPath: String, macOSTestShimPath: String) {
    assert(!iOSSimulatorTestShimPath.isEmpty)
    assert(!macOSTestShimPath.isEmpty)
    self.iOSSimulatorTestShimPath = iOSSimulatorTestShimPath
    self.macOSTestShimPath = macOSTestShimPath
  }

  // MARK: Lookup

  private static func pathForCanonicallyNamedShim(_ shim: CanonicalShim, inDirectory directory: String) async throws -> String {
    let shimPath = (directory as NSString).appendingPathComponent(shim.filename)
    guard FileManager.default.fileExists(atPath: shimPath) else {
      throw FBXCTestShimError.shimMissing(path: shimPath)
    }
    guard shim.codesigningRequired else {
      return shimPath
    }
    let codesign = FBCodesignProvider.codeSignCommand(withIdentityName: "-", logger: nil)
    do {
      _ = try await bridgeFBFuture(codesign.cdHashForBundle(atPath: shimPath))
    } catch {
      throw FBXCTestShimError.shimUnsigned(path: shimPath, underlying: error)
    }
    return shimPath
  }

  public static func findShimDirectory() async throws -> String {
    guard let searchPath = BundledResources.directoryPath() else {
      throw FBXCTestShimError.searchPathUnresolvable
    }
    do {
      return try await confirmExistenceOfRequiredShims(inDirectory: searchPath)
    } catch {
      throw FBXCTestShimError.shimsMissingInDirectory(shimNames: CanonicalShim.allCases.map(\.filename), directory: searchPath, underlying: error)
    }
  }

  private static func confirmExistenceOfRequiredShims(inDirectory directory: String) async throws -> String {
    guard FileManager.default.fileExists(atPath: directory) else {
      throw FBXCTestShimError.shimDirectoryMissing(directory: directory)
    }
    async let iOSSimulatorShim = pathForCanonicallyNamedShim(.iOSSimulatorTest, inDirectory: directory)
    async let macShim = pathForCanonicallyNamedShim(.macTest, inDirectory: directory)
    _ = try await (iOSSimulatorShim, macShim)
    return directory
  }

  // Caches the first resolution for the life of the process; actor isolation ensures exactly one resolution
  // runs even when first callers race.
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

  public static func sharedShimConfiguration() async throws -> FBXCTestShimConfiguration {
    try await sharedResolution.configuration()
  }

  public static func defaultShimConfiguration() async throws -> FBXCTestShimConfiguration {
    let directory = try await findShimDirectory()
    return try await shimConfiguration(withDirectory: directory)
  }

  public static func shimConfiguration(withDirectory directory: String) async throws -> FBXCTestShimConfiguration {
    _ = try await confirmExistenceOfRequiredShims(inDirectory: directory)
    async let iOSSimulatorTestShimPath = pathForCanonicallyNamedShim(.iOSSimulatorTest, inDirectory: directory)
    async let macOSTestShimPath = pathForCanonicallyNamedShim(.macTest, inDirectory: directory)
    return try await FBXCTestShimConfiguration(
      iOSSimulatorTestShimPath: iOSSimulatorTestShimPath,
      macOSTestShimPath: macOSTestShimPath)
  }

}
