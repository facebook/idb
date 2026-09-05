/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import XCTest

final class FBXCTestShimConfigurationTests: XCTestCase {
  private static let iOSShimName = "libShimulator-iOS.dylib"
  private static let macOSShimName = "libShimulator-macOS.dylib"

  /// Empty placeholder files suffice: codesignature validation is off unless the override env var is set.
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

  func testShimConfigurationResolvesRenamedShims() async throws {
    let dir = try makeShimDirectory()
    defer { try? FileManager.default.removeItem(atPath: dir) }

    let config = try await FBXCTestShimConfiguration.shimConfiguration(withDirectory: dir)

    XCTAssertEqual(config.iOSSimulatorTestShimPath, (dir as NSString).appendingPathComponent(Self.iOSShimName))
    XCTAssertEqual(config.macOSTestShimPath, (dir as NSString).appendingPathComponent(Self.macOSShimName))
  }
}
