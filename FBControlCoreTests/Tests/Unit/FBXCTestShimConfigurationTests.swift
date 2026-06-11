/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import XCTest

/// Tests for the runtime shim lookup in `FBXCTestShimConfiguration`. These cover the renamed
/// shim dylibs (`libShimulator-iOS.dylib` / `libShimulator-macOS.dylib`) being resolved from a
/// shim directory, and the `TEST_SHIMS_DIRECTORY` override that selects that directory.
final class FBXCTestShimConfigurationTests: XCTestCase {
  private static let iOSShimName = "libShimulator-iOS.dylib"
  private static let macOSShimName = "libShimulator-macOS.dylib"

  /// Creates a fresh temp directory containing empty placeholder files for the two shims the
  /// lookup requires. Codesignature validation is off by default (`confirmCodesignaturesAreValid`
  /// returns false unless the override env var is set), so empty placeholder files are sufficient.
  private func makeShimDirectory() throws -> String {
    let dir = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("idb-shim-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for name in [Self.iOSShimName, Self.macOSShimName] {
      let path = (dir as NSString).appendingPathComponent(name)
      guard FileManager.default.createFile(atPath: path, contents: Data()) else {
        throw CocoaError(.fileWriteUnknown)
      }
    }
    return dir
  }

  func testShimConfigurationResolvesRenamedShims() throws {
    let dir = try makeShimDirectory()
    defer { try? FileManager.default.removeItem(atPath: dir) }

    let config = try FBXCTestShimConfiguration.shimConfiguration(withDirectory: dir, logger: nil).await()

    XCTAssertEqual(config.iOSSimulatorTestShimPath, (dir as NSString).appendingPathComponent(Self.iOSShimName))
    XCTAssertEqual(config.macOSTestShimPath, (dir as NSString).appendingPathComponent(Self.macOSShimName))
  }

  func testFindShimDirectoryUsesEnvironmentOverride() throws {
    let dir = try makeShimDirectory()
    defer { try? FileManager.default.removeItem(atPath: dir) }

    setenv(FBXCTestShimDirectoryEnvironmentOverride, dir, 1)
    defer { unsetenv(FBXCTestShimDirectoryEnvironmentOverride) }

    let found = try FBXCTestShimConfiguration.findShimDirectory(
      onQueue: DispatchQueue(label: "FBXCTestShimConfigurationTests"),
      logger: nil
    ).await()

    XCTAssertEqual(found, dir as NSString)
  }
}
