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

  func testItemInLoadedBundleResources() {
    // `photo0.png` ships in this test bundle's resources, not alongside `Bundle.main`'s
    // executable (the test runner).
    // BUG: returns nil because lookup only consults `Bundle.main`'s layouts, so a host whose
    // resources live in a loaded bundle cannot resolve them — flipped in the following commit.
    XCTAssertNil(BundledResources.path(forItem: "photo0.png"))
  }
}
