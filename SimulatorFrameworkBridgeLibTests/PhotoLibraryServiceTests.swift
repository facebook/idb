/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeLib
import XCTest

final class PhotoLibraryServiceTests: XCTestCase {

  func testUnknownActionReturnsFailure() {
    XCTAssertEqual(handlePhotoLibraryAction("delete"), 1)
    XCTAssertEqual(handlePhotoLibraryAction(""), 1)
    XCTAssertEqual(handlePhotoLibraryAction("add"), 1)
  }
}
