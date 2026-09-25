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
}
