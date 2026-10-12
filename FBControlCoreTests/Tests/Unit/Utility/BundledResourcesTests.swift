/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class BundledResourcesTests: XCTestCase {

  func testMissingItemIsNotFound() {
    XCTAssertNil(BundledResources.path(forItem: "does-not-exist-anywhere"))
  }

  func testItemInLoadedBundleResources() throws {
    // `photo0.png` ships in this test bundle's resources, not alongside `Bundle.main`'s
    // executable (the test runner).
    let path = try XCTUnwrap(BundledResources.path(forItem: "photo0.png"))
    XCTAssertTrue(FileManager.default.fileExists(atPath: path))
  }

  func testAHostDirectoryIsTheResourcesDirectory() throws {
    let directory = try makeHostDirectory(containing: "SimulatorFrameworkBridge")
    BundledResources.hostDirectoryPath = directory
    defer { BundledResources.hostDirectoryPath = nil }

    XCTAssertEqual(BundledResources.directoryPath(), directory)
    XCTAssertEqual(
      BundledResources.path(forItem: "SimulatorFrameworkBridge"),
      (directory as NSString).appendingPathComponent("SimulatorFrameworkBridge"))
  }

  func testAnItemMissingFromTheHostDirectoryIsStillFoundInLoadedBundles() throws {
    BundledResources.hostDirectoryPath = try makeHostDirectory(containing: "SimulatorFrameworkBridge")
    defer { BundledResources.hostDirectoryPath = nil }

    let path = try XCTUnwrap(BundledResources.path(forItem: "photo0.png"))
    XCTAssertTrue(FileManager.default.fileExists(atPath: path))
  }

  func testWithoutAHostDirectoryTheRunningBundleDecides() {
    XCTAssertNil(BundledResources.hostDirectoryPath)
    XCTAssertNotNil(BundledResources.directoryPath())
  }

  private func makeHostDirectory(containing item: String) throws -> String {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    FileManager.default.createFile(atPath: directory.appendingPathComponent(item).path, contents: Data())
    return directory.path
  }
}
